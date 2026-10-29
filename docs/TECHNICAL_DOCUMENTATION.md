# TECHNICAL DOCUMENTATION: Roguelite card-tactics game (Godot 4.4+, GDScript)

Companion of `PROJECT_CONTEXT.md` (design, decisions, collaboration rules, backlog).
This file documents **the code as delivered**: architecture, scripts, APIs, signals, scene trees to build, data model, save format, workflows.

> Status legend: **[T]** tested/confirmed by the developer, **[U]** delivered but not confirmed yet.
> **[T]**: phases 1 to 7 (hub buildings and carpentry included), the pause menu, saves, the status icon row (Evasion included) and the character UI placement/labels.
> **[U]**: Bleeding / Stun ticking, Cleanse, armor/heal cards, the gate grid fit, the rebuilt `Expedition.tscn`.
> **[T] added in this revision**: the gate map (expedition selection before the team selection): site picking, Choose Team, destination reaching the run, Back button, Esc closing the gate, Hub menu layer.
> **[D]** = exists in the project but its file was not shared with the documentation author (now only `tools/make_enemy_catalog.gd` and `CardData.closest_in_range`, which `battle.gd` calls).

**Changes in this revision**
* New **gate map** (section 7.4): the gate building now opens `menu_gate_map`, where the player picks an expedition on a map of `ExpeditionSite`s, then `menu_gate` for the team.
* New `ExpeditionSite` (Area2D), `expedition_site.tscn` and the **unlock conditions** (`UnlockCondition` and subclasses, section 3.6). `ExpeditionData` has the matching `unlock_conditions` / `locked_display` / `unlock_hint` (3.4) and `PlayerProfile` the `completed_expeditions` list (2.3, saved). The conditions are defined but **not applied yet** by the gate map.
* `ExpeditionData` also has enemy tags and a threat budget for generated fights (3.4).
* `menu_gate.gd`: the destination is now `expedition_id` (set by the opener), no longer a constant. `title_label` export added.
* `Hub.gd`: menus are opened on a dedicated `CanvasLayer` at **layer 2** (see the layer convention in section 0).
* **Enemy actions and intents** (3.7, 4.6): enemies pick weighted `EnemyAction`s (melee, ranged, AOE, buff, debuff, heavy with wind-up), announce them as an `EnemyIntent` (head icon + name above the enemy, AOE circle on the ground), and carry them out on their next turn. Documented from `EnemyAction`, `EnemyIntent`, `IntentOverlay`, `CharacterData`, `character.gd` and `battle.gd`.
* **Cards that spend a status** (arcane charges, 3.2 / 3.3b / 4.4b): `CardData.consume_status`, `consume_amount`, `bonus_damage_per_stack`, `consume_required`; `Battle.get_charges_to_spend` / `get_charge_bonus_damage`.
* **Statuses: Sleep** (3.3): like Stun, but any hit that damages the sleeper removes it (`Character.take_hit` → `StatusComponent.wake_up`). `Battle` now checks `is_incapacitated()` instead of `is_stunned()`.
* **Statuses: scaling Bleeding and Poison** (3.3, 5.3): `StatusData.tick_damage`; Bleeding now deals `tick_damage x stacks`, a new `POISON` effect deals a flat `tick_damage`; `StatusComponent.consume_all` added for stacks spent by cards (arcane charges, planned, 3.3b).
* **Generated encounters** (3.8): `EncounterData.fill_with_pool`, `EnemyCatalog` and `EncounterGenerator` build a fight from the expedition's enemy tags and a threat budget.

---

## 0. Conventions

* Godot **4.4+**. GDScript with static typing. Typed `Dictionary[StringName, int]` and `@export_tool_button` are used.
* **Ids are `StringName`** (`&"knight"`). They are stored as strings in JSON and converted back (`SaveUtils`).
* Data = **Resources** (`.tres`). Runtime state = `RefCounted` classes holding only ids / ints / lists (serializable).
* Scene internals are reached with **unique names** (`%Name`, "Access as Unique Name" in the editor). Scripts for UI often use `@export` slots instead; each script header lists what it needs.
* Rules live in `Battle`; UI scripts only read them and emit/connect signals.
* Autoloads: `GameState`, `SceneManager`, `PauseMenu` (no `class_name` on these scripts).
* The developer designs for **1920x1080**; the character `UI` node is scaled down (about 0.27), so pixel constants in `character.gd` are large (see 5.1).
* **CanvasLayer order is global.** Godot sorts every `CanvasLayer` by its `layer` number, **not** by nesting: two layers with the same number are drawn in an undefined order, whatever their place in the tree.
  Convention in the hub: resource bar layer 1 (default), **menus opened by the Hub on layer 2** (`Hub._menu_layer`), the gate map's own `%UI` layer for the menu it opens (the team menu) on layer **10**. A deeper menu level needs a number above the previous one.
* The developer's project layout: `scripts/{battle,cards,components,CharacterData}`, `scenes/{UI,character,battle.tscn,...}`, `data/{cards,character,TileSet,...}`, `assets/`, `addons/crt`.
  File names in the delivered code are mixed (`battle.gd`, `CardData.gd`/`card_data.gd`...). Only the `class_name` matters.

---

## 1. Architecture overview

```
 Main menu ──New/Load/Continue──► Hub ──Gate: map (expedition) ► team menu──► Expedition screen ◄──► Battle scene
    ▲                              │ carpentry/tavern/forge        │  (graph, camp, events)     (cards, enemies)
    │                              ▼                               ▼
    └──────── Pause menu ◄── (available everywhere except main menu)    end of run ─► loot into profile ─► Hub

 Autoloads:  SceneManager (route + fade)   GameState (profile, run, catalogs, saves)   PauseMenu (Esc)
 Persistent: PlayerProfile (heroes, resources, buildings)     Temporary: RunState (team, health, node, loot)
 Data:       HeroCatalog / ExpeditionCatalog / BuildingCatalog  (.tres, validated at startup)
```

Flow of one expedition: gate building → `menu_gate_map` (pick a site, `expedition_id`) → `menu_gate` (pick the team) → `menu_gate.launch()` → `GameState.start_run()` → `SceneManager.go_to(&"expedition")` →
`expedition.gd` enters the START node and saves → player clicks a node → `RunState.enter_node()` →
battle node: `SceneManager.go_to(&"battle")` → `Battle._start_from_run()` → battle ends → `_record_result()` writes health + `battle_result` into the run →
`leave_battle()` → expedition `_ready()` → `_resume_node()` reads the result, resolves the node (loot, save) → ... → END node or abandon or defeat →
`GameState.end_run()` (loot into profile, save) → `SceneManager.go_to(&"hub")`.

---

## 2. Autoloads and global state

### 2.1 `SceneManager` (`SceneManager.gd`, extends CanvasLayer, layer 100)
* `ROUTES` (const dict): `&"main_menu"`, `&"hub"`, `&"expedition"`, `&"battle"` → `res://scenes/*.tscn` (**adjust paths to the project**).
* `go_to(route) -> bool` (coroutine): fades to black, `change_scene_to_file`, waits two frames, fades in. Returns false immediately if the route is missing/unavailable or a change is in progress (warning printed). Blocks clicks during the fade.
* `is_changing() -> bool`: true during a change (used by the pause menu).

### 2.2 `GameState` (`GameState.gd`, extends Node)
Variables: `hero_catalog`, `expeditions` (ExpeditionCatalog), `buildings` (BuildingCatalog), `profile` (PlayerProfile), `run` (RunState or null),
`can_save` (false until a game is started from the main menu), `save_slot`, `save_name`, `load_error`.
Catalog paths (const): `res://data/hero_catalog.tres`, `res://data/expedition_catalog.tres`, `res://data/building_catalog.tres`. Catalogs are validated in `_ready()` (warnings in Output).
`_ready()` creates a **default test profile** so any scene can be run alone (F6); it is never saved (`can_save` false).

| Method | Purpose |
|---|---|
| `new_game(game_name := "")` | Fresh profile (starting heroes + `built_at_start` buildings), new save slot, `can_save = true`, writes the file immediately. Empty name becomes "New game". |
| `list_saves() / latest_save_slot() / has_save()` | Wrap `SaveManager`. |
| `save_game() -> bool` | Writes `{name, profile, run}` into `save_slot`. No-op (false) if `can_save` is false or no slot. |
| `load_game(slot_id) -> bool` | Replaces profile/run, sets `save_slot`/`save_name`, `can_save = true`. Ensures starting buildings exist (older saves). Drops an invalid run with a warning that says why (`_is_run_valid`). On failure `load_error` is set. |
| `get_unlocked_heroes()` | Allies unlocked in the profile (catalog order). |
| `_ensure_starting_heroes()` (private) | Unlocks every catalog hero with `unlocked_by_default`. Run on `new_game` **and on every `load_game`**, so heroes added to the catalog later also appear in old saves. |
| `get_run_team() / get_run_fighters()` | Heroes of the run / those with health > 0. |
| `get_building_level(id)`, `are_requirements_met(b)`, `get_next_building_level(b)`, `can_upgrade_building(b)`, `upgrade_building(b)` | Buildings logic. `upgrade_building` pays, sets the level, unlocks the location, **saves**. |
| `has_run()`, `get_run_expedition()`, `start_run(expedition_id, team)` | Run access. |
| `end_run(completed) -> {"loot", "bonus"}` | Moves the run loot into the profile (**always 100%**), adds `completion_bonus` only if `completed`, clears the run, **saves**. |

### 2.3 `PlayerProfile` (RefCounted, persistent)
Fields: `unlocked_heroes: Array[StringName]`, `resources: Dictionary` (id → int), `unlocked_locations: Array[StringName]`, `upgrade_levels: Dictionary` (building id → level), `completed_expeditions: Array[StringName]` (expeditions finished at least once).
Signals: `resources_changed`, `locations_changed`.
Methods: `unlock_hero`, `is_hero_unlocked`, `get_resource`, `add_resource`, `can_afford(cost)`, `spend(cost) -> bool`, `unlock_location`, `is_location_unlocked`, `get_upgrade_level`, `set_upgrade_level`, `complete_expedition(id)` (idempotent), `is_expedition_completed(id)` (used by `UnlockCompletedExpedition` and the gate map), `to_dict()`, `static from_dict(d)`.
`completed_expeditions` is saved (`"completed_expeditions"`); a save from an older version simply has none. **Who calls `complete_expedition` was not shared** (expected: `GameState.end_run(true)`; to verify, see the checklist).
A building is "built" when its location is unlocked and its level is ≥ 1.

### 2.4 `RunState` (RefCounted, temporary, serializable)
Fields: `expedition_id`, `team: Array[StringName]`, `hero_health: Dictionary` (hero id → current health), `current_node_id`, `visited_nodes`,
`node_resolved: bool`, `battle_result: BattleResult {NONE, VICTORY, DEFEAT}`, `loot: Dictionary`.
Methods: `static start(expedition_id, heroes)` (heroes at full `max_health`, TODO forge upgrades), `enter_node(id)` (sets `node_resolved = false`, resets `battle_result`),
`resolve_node()`, `get_health`, `set_health`, `is_hero_alive` (>0), `add_loot`, `to_dict()`, `static from_dict(d)`.
**Rule:** the next node can only be chosen when `node_resolved` is true.

### 2.5 `HeroCatalog` (Resource)
`heroes: Array[CharacterData]`, `get_hero(id)`, `validate()` (warns on empty/duplicate ids). **Every hero `.tres` needs a unique non-empty `id`.**

---

## 3. Data model (Resources)

### 3.1 `CharacterData` (heroes and enemies)
| Field | Notes |
|---|---|
| `id`, `display_name`, `team` (`ALLY`/`ENEMY`) | id required for saves. |
| `unlocked_by_default` | Hero is part of a new game's roster. |
| `tileset`, `tile_coords` (in tiles), `size_in_tiles`, `head_position` (px, default (16, 8)) | Sprite cut from the tileset. |
| `max_health`, `starting_armor` | Armor is a health layer, not a status. |
| `starting_statuses: Dictionary[StatusData, int]` | Statuses applied at spawn through `Character.apply_status` (e.g. Evasion 2, Bleeding 1). Replaces the removed `starting_evasion`. |
| `deck: Array[CardData]` | Heroes: cards added to the shared pile. |
| `actions: Dictionary[EnemyAction, int]` | Enemies: what it can do on its turn, **action → weight** (higher = more often; `{goblin_stab: 3, goblin_throw: 1}` stabs 3 times out of 4). One usable action is picked at random each turn (rules in 4.6: negative weight counts as 0, all weights 0 = equal chances, a 0 next to positive weights is never picked). **No action = a basic melee attack with a warning** (replaces the removed `attack_damage` / `attack_range`). See 3.7. |
| `tags: Array[StringName]` | Enemies: where it lives ("forest", "catacombs"). It can be picked for an expedition sharing at least one of its `enemy_tags` (3.4). |
| `threat` (1 to 99) | Enemies: cost in the threat budget of a generated battle (goblin 2, hobgoblin 6...). A strong enemy never appears while the budget is lower. |
Helpers: `get_sprite_texture()`, `get_head_texture(size := 16x16)` (AtlasTexture crops, clamped inside the sprite).

### 3.2 `CardData` (static card, shared) and `CardInstance` (runtime)
`@tool` script (the inspector hides irrelevant fields).
* Identity: `id`, `display_name`, `description`, `art`.
* Type & mana: `card_type` (`ATTACK`/`SUPPORT`/`MANA`), `mana_generation` (hidden for MANA), `mana_cost` (MANA only).
* Damage: `damage`, `knockback` (`NONE`/`STANDARD`/`FORCEFUL`), `critical`.
* Rules: `quick`.
* Consume (all hidden except `consume_status` while it is empty): `consume_status: StatusData` (a status the caster spends when playing the card, e.g. arcane charges), `consume_amount` (0 = all the caster has), `bonus_damage_per_stack` (added to **each hit**, before the critical multiplier), `consume_required` (the card cannot be played unless the caster holds at least `consume_amount` stacks, at least 1 when it is 0). See 3.3b.
* Targeting: `target_team`, `target_type`, `max_targets` (MULTIPLE/CHAINED), `select_radius` (MULTIPLE, 0 = unlimited), `chain_radius` (CHAINED), `aoe_radius` (AOE). All radii in **pixels**.
* Movement: `approach_distance` (max distance to the target, default 32), `use_approach_angle`, `approach_angle` (degrees, relative to the direction the caster comes from; 0 same side, 180 behind, ±90 flanks; positive = clockwise on screen).
* Effects: `effects: Array[StatusApplication]`.
* Methods: `get_approach_position(caster_pos, target_pos)`, `static closest_in_range(from, to, max_distance)`.

`CardInstance` (RefCounted, created when drawn): `data`, `caster` (hero who owns it), copies of `damage`, `critical`, `mana_generation`, `mana_cost` (buff cards edit these), `get_effects(trigger)`.
(The developer customized their `CardInstance.gd`, e.g. extra display fields. Ask before editing.)

### 3.3 `StatusData` and `StatusApplication`
`StatusData` (`@tool`, the inspector hides irrelevant fields):

| Field | Notes |
|---|---|
| `id`, `display_name`, `description`, `icon` | The icon is shown in the character's status row. |
| `effect: Effect` | `NONE, ARMOR, HEAL, EVASION, BLEED, STUN, CLEANSE, POISON, SLEEP`. **Append only** (saved as integers). Decides the behaviour (below). |
| `debuff: bool` | Marks a negative status so `CLEANSE` removes it. `BLEED`, `POISON`, `STUN` and `SLEEP` are always debuffs. |
| `duration_type: DurationType` | `TURNS` (decays at the end of the owner's side phase) or `USES` (only consumed). Hidden for instant effects. |
| `decay_per_turn` | TURNS only, default 1 (0 = never expires). |
| `tick_damage` (0 to 999, default 1) | BLEED / POISON: damage dealt at the start of the owner's turn (BLEED: `tick_damage x stacks`; POISON: `tick_damage`, see below). A resource saved before this field existed gets 1, so an old Bleeding keeps dealing `stacks` damage. |
| `bypass_armor` | BLEED / POISON, default true (damage goes straight to health). |

What `stacks` means per effect:

| Effect | Stacks | Where it lives |
|---|---|---|
| `ARMOR` | armor points added (50 = +50 armor, 1 point = 1 hp), instant | `HealthComponent` |
| `HEAL` | health restored, instant | `HealthComponent` |
| `CLEANSE` | ignored (use 1; 0 is filtered out before the effect), removes all debuffs from the target, instant | `StatusComponent` |
| `BLEED` | **intensity**: each start of the owner's turn it deals `tick_damage x stacks`, then loses `decay_per_turn` (stack more = hits harder, e.g. `tick_damage` 2, Bleeding 3: 6, then 4, then 2) | `StatusComponent` |
| `POISON` | **duration only**: each start of the owner's turn it deals a flat `tick_damage` whatever the stacks, then loses `decay_per_turn` (more stacks = lasts longer, never stronger: spread it over several enemies) | `StatusComponent` |
| `STUN` | turns skipped, `- decay_per_turn` per turn | `StatusComponent` |
| `SLEEP` | same as STUN (cannot act, `- decay_per_turn` per turn) **but removed at once when the owner is hit**: any hit that is not dodged (even if armor absorbs it) wakes it. Bleeding / Poison ticks do not wake it. Cleanse removes it | `StatusComponent` |
| `EVASION` | `USES`: each stack dodges one hit (consumed); `TURNS`: dodges every hit while it lasts | `StatusComponent` |
| `NONE` | plain marker; with `USES` duration it is also how a **stack that cards consume** (arcane charges) is authored: it never decays | `StatusComponent` |

Helpers: `get_effect()` (an old resource with effect `NONE` and id `&"evasion"` still counts as EVASION), `is_value_effect()` (ARMOR/HEAL), `is_debuff()` (BLEED, POISON, STUN, SLEEP or the `debuff` box), `is_tick_effect()` (BLEED or POISON), `get_tick_damage(stacks)` (0 for other effects),
`get_display_number(stacks)` (the number drawn on the icon: **the stacks for BLEED** (the intensity); otherwise the turns left = `ceil(stacks / decay_per_turn)` for expiring TURNS statuses, or the stacks).

`StatusApplication`: `trigger` (`ON_PLAY`/`ON_KILL`), `recipient` (`TARGET`/`SELF`), `status`, `stacks`. With ON_KILL only SELF makes sense. **Stacks must be >= 1.**
Resources to author: `armor`, `heal`, `cleanse` (instant), `bleeding` (BLEED, TURNS, decay 1, `tick_damage` as wanted), `poison` (POISON, TURNS, decay 1, `tick_damage` e.g. 4), `stun` (STUN, TURNS, decay 1), `sleep` (SLEEP, TURNS, decay 1), `evasion` (EVASION, **USES**), plus an icon each.

### 3.3b Status roadmap: Poison and arcane charges
* **Poison**: done at the data level (`POISON` effect, flat `tick_damage`, duration = stacks). Author `poison.tres` and give it to a card or an enemy `EnemyAction` like Bleeding. [U]
* **Arcane charges (stack, then spend)** [U]: authored as a status with effect `NONE` and duration `USES` (never decays, shown with its stack count). Cards **give** it with a `StatusApplication` on SELF (recipient `SELF`, trigger `ON_PLAY`), and other cards **spend** it with the `CardData` "Consume" fields (3.2). At resolution (`Battle.play_card`, step 2b) the stacks are read and spent **once per card**: `spent = min(held, consume_amount)` (`consume_amount` 0 = all), removed with `status_component.consume`, and every hit gets `bonus_damage_per_stack x spent`. A chain or an AOE gives the same bonus to each of its hits. A card with 0 base damage and a bonus still hits. The spending happens **before** the card's own statuses, so a card can spend charges and give new ones. `get_charges_to_spend(card)` and `get_charge_bonus_damage(card)` are public so the card UI can preview the bonus (not done yet). Only damage uses the charges for now; other consumers (extra healing, a status consumed on hit, extra effects per charge) can reuse `get_charges_to_spend`.

### 3.4 Expedition data
* `ExpeditionNode` (`@tool`): `id`, `type` (`START, BATTLE, BOSS, CAMP, EVENT, END`), `title`, `description`, `next_nodes: Array[StringName]`, `encounter` (BATTLE/BOSS), `loot: Dictionary[StringName,int]`, `lane` (-1 top … 1 bottom, map layout hint). `has_encounter()`.
* `EncounterData` (`@tool`): `enemies: Array[CharacterData]` (always present; the whole fight when `fill_with_pool` is off), `fill_with_pool: bool` (add enemies from the expedition's pool until the threat budget is spent, see 3.8), `objective_scene: PackedScene` (root extends `BattleObjective`; empty = kill all), `spawn_pattern` (`STANDARD, AMBUSH, AMBUSHED`; only STANDARD implemented).
* `ExpeditionData` (`@tool`): `id`, `display_name`, `description`, `goal` (shown in the gate menu), `completion_bonus: Dictionary[StringName,int]`, `nodes`, plus three groups:
  * **Unlock**: `unlock_conditions: Array[UnlockCondition]` (all must be met; empty = always available), `locked_display` (`enum LockedDisplay { HIDDEN, TEASED }`, what the map shows while locked), `unlock_hint` (text of a teased site; empty = built from the conditions' `describe()`).
  * **Enemies**: `enemy_tags: Array[StringName]` (tags of the enemies living here), `base_budget` (threat budget of a battle at depth 0, default 2), `budget_per_depth` (added per column, default 2). Used by generated fights: `EncounterData.fill_with_pool`, `EnemyCatalog.get_pool(tags)` (matches `CharacterData.tags`) and `CharacterData.threat` (3.1). See 3.8 for `EnemyCatalog` and `EncounterGenerator`.
  * **Graph**: `nodes`.
  Helpers: `get_node_by_id`, `get_start`, `get_end_nodes`, `get_next_nodes(id)`, `get_depths()` (column per node, longest path), `get_budget(node)` (`base_budget + budget_per_depth * depth + node.difficulty_bonus`, never below 0), `get_enemy_pool()` (enemies of the `EnemyCatalog` sharing a tag; empty if there is no catalog), `validate() -> Array[String]`
  (empty unlock condition entries, unique ids, exactly one START, ≥ 1 END, valid links, no cycle, no dead end, all reachable, battles have enemies or `fill_with_pool`; then, for generated fights: a catalog exists, the tags match at least one enemy, and the budget can pay the cheapest enemy). An inspector button "Validate graph" prints the result.
* `ExpeditionCatalog`: `expeditions`, `get_expedition(id)`, `validate()`.

### 3.5 Building data (hub)
* `BuildingLevel`: `cost: Dictionary[StringName,int]`, `description`.
* `BuildingData`: `id` (**must equal the `location_id` of its `HubLocation`**), `display_name`, `description`, `built_at_start`, `requires: Dictionary[StringName,int]` (building id → min level), `levels: Array[BuildingLevel]` (`levels[0]` = construction = level 1, then upgrades). `get_max_level()`, `get_level_data(level)` (1-based).
* `BuildingCatalog`: `buildings`, `get_building(id)`, `validate()` (empty/duplicate ids, no levels, unknown requirements).

### 3.6 Unlock conditions (resources) [T for definition, not applied yet]
Requirements for an expedition location of the map to be available. Authored in the inspector ("Add element" > "New ...").
* `UnlockCondition` (Resource, base): `is_met(profile: PlayerProfile) -> bool` (base: always true), `describe() -> String` (short text for the player, base: empty).
* `UnlockBuildingLevel`: `building_id`, `level` (1 to 20). Met when `profile.get_upgrade_level(building_id) >= level`. `describe()`: "Build the X" / "Upgrade the X to level N" (name from `GameState.buildings`).
* `UnlockCompletedExpedition`: `expedition_id`. Met when `profile.is_expedition_completed(expedition_id)`. `describe()`: `Complete "Name"`.
* To add a kind of requirement (a hero unlocked, an amount of a resource...): new script extending `UnlockCondition`, override `is_met` and `describe`. It then appears in the list.
* The list lives in `ExpeditionData.unlock_conditions` (3.4), with `locked_display` and `unlock_hint` for what the map shows while it is locked. `validate()` flags empty entries.
**Nothing evaluates the list yet**: the gate map shows every site as `UNLOCKED` (see 7.4, "To do").

### 3.7 Enemy actions (`EnemyAction`, `EnemyIntent`, `IntentOverlay`) [T]
**`EnemyAction`** (`@tool` Resource, one `.tres` per action, listed in `CharacterData.actions` with a weight). Fields:
| Field | Notes |
|---|---|
| `id`, `display_name` | Name shown next to the enemy while the action is planned. Empty = the kind name. |
| `kind: Kind` | `MELEE, RANGED, AOE, BUFF, DEBUFF, HEAVY`. **Append only if actions are stored in saved data** (they are not saved today: an intent is runtime only). Changing it refreshes the inspector (fields are hidden per kind). |
| `damage` | Damage of each hit. Hidden for BUFF (`get_damage()` returns 0 for it). **Default 5: a DEBUFF must be set to 0 by hand.** |
| `approach_distance` (px, default 32) | The enemy walks until it is at most this far from its target (or from the AOE spot). Already close enough: it does not move. |
| `aoe_radius` (AOE only, default 80) | Radius of the ground circle; every hero inside is hit. |
| `windup_turns` (HEAVY only, 0 to 10, default 1) | Enemy turns spent charging before the strike (1 = does nothing this turn, hits on the next one). `get_windup_turns()` is 0 for every other kind. |
| `can_target_self` (BUFF only) | The buffing enemy may pick itself. |
| `effects: Array[StatusApplication]` | Statuses applied when the action resolves. Recipient `TARGET` = who is hit (or the buffed enemy), `SELF` = the enemy. **Only effects whose trigger is `ON_PLAY` are applied** by `Battle._apply_action_effects` (any other trigger is skipped), so leave the trigger on `ON_PLAY`. |

Suggested values (from the script): MELEE damage 5 / distance 32; RANGED 4 / 160; AOE 6 / 200 / radius 80; BUFF distance 150, effects on TARGET or SELF; DEBUFF damage 0 / 160, effects on TARGET (Bleeding, Stun...); HEAVY 15 / 32 / wind-up 1.
Helpers: `get_damage()`, `get_windup_turns()`, `targets_own_side()` (true for BUFF only: everything else aims at the heroes), `get_intent_text(windup_left)` (name, plus the wind-up turns left: "Heavy 1"), `get_color()` (text color above the enemy: BUFF green, DEBUFF violet, HEAVY orange, AOE red, others white).

**`EnemyIntent`** (RefCounted, runtime only, never saved): what an enemy decided for its **next** turn. Created by `Battle._plan_intent`, stored in `Character.intent`. Fields: `action`, `target: Character` (the hero to hit, or the enemy to buff; **null for AOE**), `spot: Vector2` (AOE only: circle center, **fixed when the intent is planned**, so heroes can walk out of it), `windup_left` (starts at `action.get_windup_turns()`). `get_text()`.

**`IntentOverlay`** (Node2D, `class_name IntentOverlay`): draws the ground circle (`aoe_radius`, translucent red fill plus an edge) of the AOE intent of every enemy in `battle.enemies`. **Created by code in `Battle._ready()`**, inserted just before `%Allies` so the circles are drawn under the characters; `battle` is set by Battle before it enters the tree; it redraws on `battle.intents_changed`. Nothing to build in the editor.

**Pipeline** (from the script comments): the enemy **plans** an action and shows it to the player (text above it, AOE circle, target) → on its **next turn** it walks within `approach_distance` of the target (or of the spot), deals `damage`, applies `effects`. A HEAVY first spends `windup_turns` turns charging. How `Battle` does all this: 4.6.

### 3.8 Generated encounters (`EncounterData`, `EnemyCatalog`, `EncounterGenerator`) [U]
**`EncounterData`** (`@tool` Resource, stored in a BATTLE/BOSS node): `enemies` (guaranteed enemies, e.g. a boss), `fill_with_pool` (add more from the pool), `objective_scene` (root extends `BattleObjective`; empty = kill all), `spawn_pattern` (`STANDARD` only; `AMBUSH` / `AMBUSHED` are placeholders for `Battle._get_spawn_position`). Leave `enemies` empty for a normal generated fight.

**`EnemyCatalog`** (`@tool` Resource, one file: `res://data/enemy_catalog.tres`, constant `PATH`; built by `tools/make_enemy_catalog.gd` (not shared) or filled by hand): `enemies: Array[CharacterData]`. `get_enemy(id)`, `get_pool(tags) -> Array[CharacterData]` (ENEMY team characters sharing at least one tag), `validate()` (pushes a warning per problem: empty entry, no id, duplicated id, not on the ENEMY team, `threat < 1`). Enemies used only in hand-made encounters do not have to be listed.

**`EncounterGenerator`** (RefCounted, static): `build_enemies(expedition, node, run_seed, max_enemies = DEFAULT_MAX_ENEMIES (6))`. Called by `Battle._start_from_run()` with `GameState.run.rng_seed` and the number of `%EnemySpawns` markers as `max_enemies`.
1. No encounter on the node: empty list. Starts with `encounter.enemies`; without `fill_with_pool` that is the result.
2. Budget = `expedition.get_budget(node)` (`base_budget + budget_per_depth * depth + node.difficulty_bonus`) minus the `threat` of the guaranteed enemies.
3. Pool = `expedition.get_enemy_pool()`. Empty pool: a warning (no enemy matches the tags), nothing added.
4. Otherwise `_fill`: random number generator seeded with `hash("%d:%s" % [run_seed, node.id])`, so **the same node gives the same enemies during one run** (reloading a save cannot reroll a fight) and runs differ. It tries `ATTEMPTS = 8` random compositions: each repeatedly picks a **uniformly random affordable enemy** (`threat <= remaining budget`) until the free slots (`max_enemies` minus guaranteed enemies) are full or nothing is affordable, and keeps the composition that spends the most budget (the first one on a tie). A strong enemy therefore never appears while the budget is below its `threat`.
5. If the result is still empty (budget below the cheapest enemy and no guaranteed enemy), the cheapest enemy of the pool is used: **never an empty battle**.
6. Debug builds print `Encounter '<node id>': budget N -> enemy ids`.
Also `load_catalog()` (loads `EnemyCatalog.PATH`, `push_error` and an empty catalog if missing or of the wrong type); `build_enemies` itself reads the pool through `ExpeditionData.get_enemy_pool()`.
Note: a hand-made fight with more enemies than `%EnemySpawns` markers reuses markers (`index % count` in `_get_spawn_position`), so the extra enemies stand on top of others.

---

## 4. Battle (`battle.gd`, `class_name Battle`, Node2D)

### 4.1 Scene tree to build (`battle.tscn`)
```
Battle (Node2D, battle.gd)           exports: character_scene (developer's copy uses @onready), roster, objective
├── Map (TileMapLayer)               decor, not used by logic yet
├── TargetingOverlay (Node2D)        AFTER the Map, BEFORE Allies/Enemies (circles drawn under sprites)
├── %Allies (Node2D)   %Enemies (Node2D)
├── %AllySpawns (Node2D) / %EnemySpawns (Node2D)   Marker2D children = placeholder positions (index order)
├── TargetingController (Node)       exports: hand, overlay (battle found through owner)
└── BattleUI (Control, BattleUI.gd)  + Hand (HBoxContainer, Hand.gd) + counters, End Turn button, panels
```
Set full-screen HUD containers to Mouse Filter = Ignore (otherwise characters can't be clicked).

### 4.2 Signals
`phase_changed(phase)`, `turn_started(turn)`, `actions_changed(n)`, `mana_changed(n)`, `character_clicked(character)`, `intents_changed` (an intent was planned, re-aimed or cleared: `IntentOverlay` redraws), `card_played(card)`, `objective_updated`, `battle_ended(victory)`.
`enum Phase { SETUP, PLAYER_TURN, RESOLVING, ENEMY_TURN, ENDED }`. Constants: `ACTIONS_PER_TURN = 3`, `CRIT_MULTIPLIER = 1.5`, `KNOCKBACK_DISTANCE` (48/96), `MOVE_TIME`, `KNOCKBACK_TIME`, `ENEMY_ACTION_DELAY = 0.4`, `PLACEMENT_*`.

### 4.3 Start-up
`_ready()`: `_start_from_run()` (inside an expedition) else `roster` (battle tested alone).
`_start_from_run()`: reads the current node's `encounter`, sets `objective` from `objective_scene` if any, builds the roster = `GameState.get_run_fighters()` + `encounter.enemies`, `_in_expedition = true`.
`start_battle(characters)`: spawns by `data.team` (ally list / enemy list), faces everyone, builds the deck from the living allies, assigns enemy targets, starts the objective, starts the player turn.
Heroes spawn with their carried-over health (`Character.setup(data, start_health)`).

### 4.4 Public API (used by UI)
`can_play_card(card)`, `get_valid_targets(card)`, `get_max_picks(card)`, `allows_repeat_picks(card)` (CHAINED), `get_pickable_targets(card, selected)`, `is_valid_selection(card, selected)`,
`get_charges_to_spend(card)`, `get_charge_bonus_damage(card)` (charges the card would spend now / the extra damage per hit, for previews), `get_affected_targets(card, selected)` (AOE expansion), `find_approach_position(card, from, target)`, `get_approach_positions(card, selected)` (preview of where the caster will stand),
`play_card(card, selected)` (**coroutine, `await` it**), `end_player_turn()` (coroutine), `leave_battle()`.
Fields: `allies`, `enemies` (living only), `deck` (CardDeck), `phase`, `turn`, `actions_left`, `mana`, `encounter`, `objective`.

### 4.4b `play_card` pipeline
1. Guard (`can_play_card` + `is_valid_selection`), phase `RESOLVING`.
2. Pay: one action; mana for MANA cards. **2b. Spend the charges** (`consume_status`): `get_charges_to_spend`, `status_component.consume`, `bonus_damage` computed once.
3. If target team is ENEMY: caster walks (`_approach`: face target, tween to the free approach position, face again). Chain: hop by hop (each target: walk → hit → knockback, skipping dead ones); other types: walk to the first pick, then hit all affected targets at once.
4. `_deal_damage(card, targets, killed, bonus)`: per target, `(card.damage + bonus)` times the crit multiplier, **`Character.take_hit(amount)`** (evasion check, then armor, then health); kills detected with a "was alive" check (a chain can list a target several times).
5. `_knock_back` (survivors), `_apply_effects` (ON_PLAY SELF once, TARGET per living target; ON_KILL SELF once per kill).
6. Mana gain (non-MANA cards), Quick refund if a kill, discard, `card_played`, free dead, update facings, `_check_battle_end()`; else back to `PLAYER_TURN`.

### 4.5 Free-position search (placement)
`_find_free_position(ideal, center, mover)`: starting from the ideal spot around the target, test spots every 15° alternating sides (+15, −15, +30…); if the whole circle is blocked, grow the distance by the mover's radius (`shape.radius`), up to 4 rings; fallback to the ideal spot. Obstacles = every living character except the mover (including the target). Used by cards, previews and enemy attacks.

### 4.6 Enemy turn and intents [T, reported by the developer]
**Flow.** `end_player_turn()` → `_end_of_turn_statuses(allies)` → `await _run_enemy_turn()`: phase `ENEMY_TURN` → `_start_of_turn_statuses(enemies)` (Bleeding; deaths freed; battle end checked) → for each enemy still alive (`enemies.duplicate()`): `await _enemy_act(enemy)`, `_check_battle_end()`, wait `ENEMY_ACTION_DELAY` (0.4 s, `create_timer(delay, false)`: **frozen by the pause menu**) → `_end_of_turn_statuses(enemies)` → `_start_player_turn()`.

**`_enemy_act(enemy)`**
1. **Stunned: nothing happens.** The intent is kept, a wind-up does not progress, and the stun loses a stack at the end of the enemy phase.
2. If the intent is not valid (`_intent_is_valid`: none, or its target is gone) it is planned again; still no intent: the enemy does nothing.
3. **Wind-up:** `intent.windup_left > 0` → decrement, `enemy.refresh_intent()`, no action this turn. So a HEAVY with `windup_turns = 1` charges on one enemy phase and strikes on the next.
4. Otherwise `await _execute_intent`, then, if the enemy is still alive, **`_plan_intent` again**: the next action is announced during the player's turn.

**`_execute_intent(enemy, intent)`** (the same for every kind; only targets and numbers change):
* `focus` = `intent.spot` (AOE) or the target's position. `ideal = CardData.closest_in_range(enemy position, focus, approach_distance)` (the closest point at the right distance; no move if already in range), `destination = _free_position_at(ideal, ...)` (same free-spot search as the cards, around `focus`), the enemy faces `focus`, walks (`_move_characters`, `MOVE_TIME` 0.25 s) and faces it again.
* Targets (`_intent_targets`): AOE → **every hero within `aoe_radius` of the spot, checked at strike time** (a hero who walked away is spared); other kinds → the single target if it is still alive.
* If `get_damage() > 0`: `target.take_hit(damage)` for each target (Evasion can dodge it, armor then health). Then `_apply_action_effects`, `_free_dead()`, `_update_facings()`.
* `_apply_action_effects(enemy, action, targets)`: **only `ON_PLAY` effects run**; recipient `SELF` → the enemy, otherwise every living target (heroes, or the buffed enemy for a BUFF). The effects are applied **even when a hit was dodged by Evasion**.

**Planning an intent (`_plan_intent`)**: called for every enemy in `start_battle()` (so the first action is visible on the first player turn) and after each enemy action.
* `_pick_action` → `null` (no action possible, e.g. no hero left): `enemy.intent = null`, `intents_changed`. Otherwise a new `EnemyIntent`: AOE → `spot` = the position **of a random hero at this moment** (fixed from then on); other kinds → `target` = a random candidate. Then `enemy.intent = intent` (updates the display), `_face_intent`, `intents_changed.emit()`.
* **Choosing the action:** `_get_actions(enemy)` = `data.actions`, or `{fallback: 1}` when empty (the fallback is `EnemyAction.new()` with its defaults: MELEE, damage 5, distance 32, named "Attack"; one warning per enemy id). Actions with **no possible candidate are excluded** (`_candidates_for`: all heroes, or for a BUFF the other enemies plus itself if `can_target_self`). Weights: a negative weight counts as 0; if all are 0 the choice is uniform; otherwise a weighted roll, so an action with weight 0 next to positive ones is never picked.
* Randomness (`randi_range`, `pick_random`) is the **global, unseeded** generator: intents are not reproducible, unlike generated encounters (3.8).

**When someone dies (`_on_character_died`)**: removed from `allies` / `enemies`, hidden, freed later (`_dead`, `_free_dead`). A hero: its health is written as 0 in the run and its cards leave the deck. Every enemy whose `intent.target` was the fallen character calls `_retarget_intent`: **same action and same wind-up on a new random candidate**, or a full `_plan_intent` if the action has no candidate left. An AOE spot is never re-aimed. `intents_changed` is emitted (this also hides the circle of a dead enemy).

**Facing**: `_update_facings()` makes allies look at the closest enemy; each enemy looks at its intent (target, or the AOE spot) when it is valid, otherwise at the closest ally.

**Display (`character.gd`)**: the `intent` setter calls `refresh_intent()`: in `%IntentIcon` a 16x16 cut (`INTENT_CUTOUT_SIZE`) of the **target's head** (`CharacterData.head_position`, clipped to its sprite; hidden for AOE or when there is no target), and in the optional `%IntentLabel` the text `intent.get_text()` ("Stab", "Heavy 1") tinted with `action.get_color()` (`self_modulate`: keep the label's own font color white). `intent_target` is now a **read-only getter** derived from `intent` (null for AOE, no intent, or a freed target). Battle calls `refresh_intent()` after changing a wind-up or a target. `IntentOverlay` (3.7) redraws on `intents_changed`.

**Design points to be aware of**
* Effects of an action other than `ON_PLAY` are silently skipped.
* A dodged hit still applies the action's status effects.
* A stunned enemy keeps its planned intent (it is only re-planned if the target disappears).
* `intents_changed` is also emitted when an intent is cleared or re-aimed (the comment in `battle.gd` still says "picked a new target").

### 4.6b Status timing (player side)
`_start_player_turn()`: `turn += 1` → `_start_of_turn_statuses(allies)` (Bleeding on heroes, may kill) → `_check_battle_end()` (returns if over) → phase `PLAYER_TURN`, actions reset, draw.
`end_player_turn()`: `_end_of_turn_statuses(allies)` (decay) then the enemy turn. `can_play_card()` is false for a caster who **cannot act** (stunned or asleep: `Character.is_incapacitated()`), or when the card has `consume_required` and the caster holds too few stacks.
Helpers: `_start_of_turn_statuses(team)` (calls `StatusComponent.start_of_turn()` on each, frees dead, updates facings), `_end_of_turn_statuses(team)` (`end_of_turn()` on each).
Known limit: a status applied to a character during **its own side's phase** also decays at the end of that same phase.

### 4.7 End of battle and expedition hand-off
`_check_battle_end()` (after every action): emits `objective_updated`; `objective.is_complete()` → victory; `allies.is_empty()` or `objective.is_failed()` → defeat.
`_end_battle` → phase `ENDED` → `_record_result(victory)`: living allies' health into the run, `run.battle_result` set → `battle_ended` signal.
`leave_battle()` (Continue button): `SceneManager.go_to(&"expedition")` or, when the battle was run alone, `reload_current_scene()`.
**No save is made in a battle.**

### 4.8 Facing
Characters are never rotated. `Character.face_towards(pos)` flips `sprite.flip_h` (art faces left). `_update_facings()`: allies → closest enemy; enemies → their intent (the target, or the AOE spot; fallback closest ally). Attackers face their real target while walking/striking.

### 4.9 Objectives
`BattleObjective` (Node): `description`, `start(battle)`, `_on_start()`, `is_started()`, `is_complete()`, `is_failed()`, `get_progress_text()`. `KillAllObjective` is the default (created when `objective` is null).
To add one: extend `BattleObjective` (it may `@export` scene nodes), make a scene with it as root, reference it from `EncounterData.objective_scene`.
Anything outside the objective that reads it must check `is_started()` first (it is null-safe only after `start()`).

### 4.10 `CardDeck` (RefCounted)
`draw_pile`, `hand`, `discard_pile`, `MAX_HAND_SIZE = 6`, signal `hand_changed`; `build_from(heroes)`, `draw_to_full()`, `discard(card)`, `remove_cards_of(hero)`; reshuffles discard when empty.

---

## 5. Characters

### 5.1 `Character` scene (`character.gd`, Node2D) — tree to build
```
Character (Node2D, character.gd)
├── %HealthComponent (Node, HealthComponent.gd)
├── %Sprite (Sprite2D, centered, may be scaled up)
├── %UI  (instance of character_ui.tscn, scaled down ~0.27 in the developer's project)
│     bars (%HealthBar, %ArmorBar, each with a Label child: %HealthValue, %ArmorValue)  +  %StatusIcons (HBoxContainer next to the bars)  +  %IntentIcon (Sprite2D above the bars)
│     (developer layout: bars in a VBox inside an HBox together with %StatusIcons). Unique names are looked up as %UI/%Name.
└── %ClickArea (Area2D)
	└── %ClickShape (CollisionShape2D with a CircleShape2D, "Local to Scene" enabled)
```
Required unique names inside the UI scene: `HealthBar`, `ArmorBar`, `HealthValue`, `ArmorValue`, `IntentIcon`. Optional: `StatusIcons` (without it statuses still work but are invisible), `IntentLabel` (Label next to the intent icon showing the planned action name; its tint comes from the action, keep its font color white; without it intents work but the name is not shown).
All generated or label Controls must use Mouse Filter = Ignore so the character stays clickable. Turn off the bars' *Show Percentage*.

Constants: `TILE_SIZE` 32, `INTENT_CUTOUT_SIZE` 16x16, `STATUS_ICON_SIZE` and `STATUS_FONT_SIZE` (pixels **before** the UI scale; developer: 80 / 40), `UI_HEIGHT_ABOVE_HEAD` (developer: 20), `CLICK_RADIUS_FACTOR`.

`setup(data, start_health := -1)`; `_apply_data()`: joins group `allies`/`enemies`, builds the AtlasTexture sprite, sets the click circle radius, `_place_ui()`, `health.initialize(max, start_health)`, `add_armor(starting_armor)`, applies every `starting_statuses` entry through `apply_status`.
Click radius: delivered formula `size.x * |sprite.scale.x| / 2 * CLICK_RADIUS_FACTOR`; **the developer uses `size.x * CLICK_RADIUS_FACTOR + 5`** (their own tweak). `shape.radius` is also the character radius used by the placement search (4.5). The circle size comes from `CharacterData.size_in_tiles`.

Signals: `clicked(character)`, `died(character)`, `statuses_changed`.
Members: `intent: EnemyIntent` (enemies only; its setter calls `refresh_intent()`: head cutout + action label), `intent_target` (**read-only**, derived from `intent`), `refresh_intent()` (public, see 4.6), `status_component: StatusComponent` (created in `_ready()`, no scene node), `statuses` (read-only view of `status_component.stacks`), `health`, `sprite`, `ui`.
Methods: `apply_status(status, stacks)` (ARMOR → `health.add_armor`, HEAL → `health.heal`, CLEANSE → `status_component.remove_debuffs()`, everything else → `status_component.add`; ignores `stacks <= 0` and dead characters),
`take_hit(amount) -> int` (**the one place damage enters a character**: `status_component.try_dodge()` returns 0, else `health.take_damage(amount, false)`, then **`status_component.wake_up()` if `amount > 0`**: a hit wakes a sleeper, damage over time never comes through here), `is_stunned()` (STUN only), `is_incapacitated()` (stunned or asleep: what Battle checks), `set_highlighted(on)`, `face_towards(pos)`, `is_ally()`, `is_dead()`.

**UI placement** (`_place_ui`, `_update_ui_position`, `_update_ui_position_later`): the head height is `data.head_position` (texture pixels from the sprite's top-left, scaled by the sprite scale);
the target for the **bottom of the health bar** is `head_y - UI_HEIGHT_ABOVE_HEAD`. `_update_ui_position()` measures the real transforms (health bar bottom expressed in the UI node's space) and sets `ui.position.y`, so the UI scene's own scale/layout does not matter;
it is re-run two frames after spawn (containers are not sized yet) and on `health_bar.item_rect_changed` (armor bar appearing/disappearing). x is left as in the scene.

**Status row** (`_refresh_status_icons`, `_make_status_entry`, `_style_status_label`): rebuilt whenever `status_component.changed` fires. One entry per stored status: icon (`TextureRect`, nearest filter, `STATUS_ICON_SIZE`) with a number label pinned to the icon's bottom-right corner
(label anchored to that corner, growing left and down: its top-right corner touches the icon's bottom-right corner); the number is `status.get_display_number(stacks)`. A status without icon is shown as text "Name 3". The row hides when empty.
**Bar values**: `_on_health_changed` writes only the current health in `%HealthValue` (the developer removed "/max"), `_on_armor_changed` writes the armor in `%ArmorValue` and hides the armor bar at 0.

### 5.2 `HealthComponent` (Node)
Signals: `health_changed(current, max)`, `armor_changed`, `evasion_changed`, `damaged`, `healed`, `dodged`, `died`.
`initialize(max_hp, current_hp := -1)`, `take_damage(amount, can_be_dodged := true, bypass_armor := false) -> int` (returns health actually lost; armor then health; **`Character.take_hit` and bleeding pass `can_be_dodged = false`**),
`heal`, `add_armor/remove_armor`, `is_dead`, `get_health_ratio`.
**Leftover:** `evasion`, `add_evasion/remove_evasion`, `evasion_changed` and `dodged` still exist in the file but nothing uses them anymore (evasion is a `StatusComponent` status). The file has not been seen since: to be removed.

### 5.3 `StatusComponent` (Node, `status_component.gd`)
Created by `Character._ready()` with `StatusComponent.new(health)` and added as a child. Holds `stacks: Dictionary` (StatusData → stacks > 0). Signal `changed`.
`add(status, amount)`, `get_stacks(status)`, `has_effect(effect)`, `is_stunned()`, `is_asleep()`, `is_incapacitated()`, `wake_up() -> bool` (removes every SLEEP status), `consume(status, amount := 1)` (for USES statuses),
`try_dodge() -> bool` (finds an EVASION status; USES loses one stack per dodge, TURNS does not lose any),
`remove_debuffs() -> bool` (removes every status whose `is_debuff()` is true),
`consume_all(status) -> int` (removes every stack, returns how many there were), `start_of_turn()` (every status with `is_tick_effect()`: `health.take_damage(status.get_tick_damage(stacks), false, status.bypass_armor)`, never dodged; stops if the owner dies),
`end_of_turn()` (TURNS statuses lose `decay_per_turn`, removed at 0),
`get_summary()` (text such as "Bleeding 3  Stunned 1", currently unused by the UI).
Instant value effects (armor, heal) never reach this component.

---

## 6. Battle UI

* **`Hand`** (HBoxContainer): mirrors `battle.deck.hand`; each card view lives in a plain `Control` **slot** so it can move. Exports: `battle` (defaults to `owner`), `card_view_scene`.
  `card_clicked(card)` signal, `set_selected_card(card)`. Refreshes playability on `actions_changed`, `mana_changed`, `phase_changed`.
  **Card view contract:** `setup(card)`, `set_playable(bool)`, `set_selected(bool)` (raises the card, tween on `position:y`), `signal clicked(card)`, variable `card`.
* **`TargetingController`** (Node): turns clicks into `play_card`. SINGLE/AOE: first click selects (AOE shows its radius, highlights who will be hit), second click on the same target (or Enter/Space) confirms; another click changes the selection.
  CHAINED: click targets in order (repeats allowed), **plays automatically when `max_targets` is reached**. MULTIPLE: click targets, confirm with Enter/Space (`auto_confirm_when_full` export).
  Right click = undo last pick (cancel if none), Esc / clicking the card again = cancel; SELF-target cards play immediately.
  Public: `confirm_selection()`, `cancel_selection()`. It draws previews through `TargetingOverlay` (auto-found if the export is empty).
  Esc handling calls `set_input_as_handled()` so the same key does not also open the pause menu.
* **`TargetingOverlay`** (Node2D): `show_preview(circles, line, badges)` / `clear()`. Circles (with optional `"color"`) are drawn under characters, the chain line and number badges above. Range circle (MULTIPLE around the caster, `chain_radius` around the last pick, AOE around the target) is yellow, the caster's destination circles are translucent green.
* **`BattleUI`** (Control): exports `battle`, `action_counter`, `mana_counter`, `end_turn_button`, optional `objective_label`, `victory_panel`, `defeat_panel`, `victory_continue`, `defeat_continue`.
  End Turn is enabled only in `PLAYER_TURN` and has focus disabled (so Enter does not trigger it). Continue buttons call `battle.leave_battle()`.

---

## 7. Hub

### 7.1 Scene tree (hub scene, route `hub`)
```
Hub (Node2D, Hub.gd)
├── TileMapLayer / decor
├── HubLocation x N        Area2D (HubLocation.gd) + CollisionShape2D + Sprite2D (assigned to `visual`), placed at FIXED positions
└── CanvasLayer (layer 1) > HBoxContainer (ResourceBar.gd)   stock display
(the menus are NOT in the scene: Hub.gd creates their CanvasLayer by code, layer 2)
```
### 7.2 Scripts
* **`Hub`**: collects every `HubLocation` below it (group `hub_locations`), hides/shows them from the profile (`_apply_unlocks`, re-run on `profile.locations_changed`), **autosaves on open**, warns about missing buildings/locations (`_check_scene`).
  Opens the menu of a clicked location on a CanvasLayer created in `_ready()` (`_menu_layer`, **layer 2**, so that a menu can open its own sub-menu on a higher layer, see section 0) and disables clicks on the town meanwhile. Signals: `location_activated(location)` (also for places with no menu), `menu_opened`, `menu_closed`. `open_menu(location)`, `is_menu_open()`.
* **`HubLocation`** (Area2D): exports `location_id` (= building id), `display_name`, `menu_scene`, `enabled`, `always_unlocked`, `visual`, `label_offset`. Hover tint + name label, click emits `activated`. `set_unlocked(bool)` (hidden and not clickable until unlocked), `set_interactive(bool)`.
* **`HubMenu`** (Control, base class of every hub menu): `signal closed`, `close()`, optional `close_button` export, closes on Esc. Subclasses calling `_ready()` must call `super._ready()`. Menu root should fill the screen with Mouse Filter = Stop.
* **`ResourceBar`** (HBoxContainer): lists owned resources ("Wood 12"), updates on `resources_changed`. `static describe(cost) -> String`.

### 7.3 Menus
* **Gate team menu** (`menu_gate.gd`, extends HubMenu): `TEAM_SIZE = 3`. It is now the **second step** of the gate: the destination is chosen first in the gate map (7.4).
  `var expedition_id: StringName` (default `DEFAULT_EXPEDITION_ID = &"first_expedition"`, used only when the menu is opened alone for testing): **the opener sets it before `add_child`**. `launch()` uses it (`GameState.start_run(expedition_id, selected_team)`) and refuses (error) an unknown expedition.
  Exports: `hero_portrait_scene`, `hero_slot_scene`, `hero_grid` (GridContainer, 3 columns), `team_slots` (HBox, 1/3 vs 2/3 layout), `launch_button`, `close_button`, `portrait_aspect` (portrait height / width, default 1.0), optional `title_label` (shows the chosen expedition's `display_name`).
  Scene: `LeftPanel` (PanelContainer) > VBox > Label + ScrollContainer (horizontal scroll off) > `HeroGrid`; `RightPanel` > `TeamSlots` + Footer (`BackButton`, `LaunchButton`).
  **Grid fit [U]**: `_setup_grid_fit()` / `_fit_grid()` size every portrait to `(scroll width - scrollbar room - gaps) / columns` so the columns fill the left panel, re-run on the scroll container's `resized`. The portrait's inner image must scale with it (TextureRect: Ignore Size + Keep Aspect Centered; Button icon: Expand Icon).
  Left: portraits of **unlocked** heroes only (`GameState.get_unlocked_heroes()`), `HeroPortrait` (Button with `%Badge` Label, toggled look = selected, number = pick order). Right: `HeroSlot` x3 (name, full sprite, stats) that share the width equally; clicking a filled slot removes the hero. Launch enabled only with 3 heroes → `GameState.start_run` + `SceneManager.go_to(&"expedition")`.
  `HeroSlot` scene: PanelContainer > VBox > `%NameLabel`, `%SpriteRect` (TextureRect, Ignore Size + Keep Aspect Centered, expand), `%StatsLabel`
  (Health / Armor / **Statuses** from `starting_statuses` via `_format_statuses()`, "-" if none / Cards).
* **Carpentry** (`menu_carpentry.gd`, extends HubMenu) [U]: scene = Control with a close button and a VBox `%BuildingList`. Lists buildings whose requirements are met: name + level, description of the next level, cost, **Build/Upgrade** button (disabled if unaffordable). Purchase = `GameState.upgrade_building()`.
* **Tavern / Forge**: buildings exist in data (via `tools/make_test_buildings.gd`) but **their menus are not written**.

### 7.4 Gate map: expedition selection [T]
Flow: gate building (`HubLocation`) → **`menu_gate_map`** (pick an expedition site, **Choose Team**) → **`menu_gate`** (pick the team, **Launch**).
Files (project paths): `scenes/hub/gate/map/menu_gate_map.{gd,tscn}`, `scenes/world_map/expedition_site.tscn`, `scripts/hub/world_map/ExpeditionSite.gd`. The gate's `HubLocation.menu_scene` points to `menu_gate_map.tscn`.

**Scene tree (`menu_gate_map.tscn`)**
```
map (Control, full rect, Mouse Filter Ignore, menu_gate_map.gd extends HubMenu)
├── Backdrop (ColorRect)
├── VBoxContainer
│   ├── %TitleLabel, %BodyLabel, %StatusLabel     (info on the selected site)
│   └── HBoxContainer: %BackButton, %ChooseTeamButton
├── %UI (CanvasLayer, layer 10)                     the team menu is added here
└── ExpeditionSiteNodes (plain node holding every ExpeditionSite instance)
```
Sites live under a dedicated `ExpeditionSiteNodes` node on purpose: `_ready()` calls `configure()` on **every child** of it, so a Backdrop or any non-site node among them would error.

**`menu_gate_map.gd`**
* Fields: `selected_expedition_id`, `currently_selected_site`; `Expedition_Site_Nodes = $ExpeditionSiteNodes`; `MENU_GATE_SCENE = preload("res://scenes/hub/gate/menu_gate.tscn")`.
* `_ready()`: `super._ready()` (this wires the Back button: **`close_button` is assigned to `%BackButton` in the inspector**, so no manual `pressed.connect` is needed), then for each child of `ExpeditionSiteNodes`: looks up `GameState.expeditions.get_expedition(site.expedition_id)`, calls `site.configure(data, ExpeditionSite.State.UNLOCKED, GameState.profile.is_expedition_completed(id))` when the data exists, and connects `site.selected` (there is no `is ExpeditionSite` guard: **every child of `ExpeditionSiteNodes` must be a site**). `%ChooseTeamButton` is connected and starts disabled.
* `_on_expedition_site_selected(site)`: deselects the previous site, selects this one, stores `selected_expedition_id`, enables Choose Team, fills the labels: title = `site.expedition.display_name`, body = `site.expedition.description`, status = `"ID: " + expedition_id` (if the site has no `ExpeditionData`: capitalised id and a generic text).
* `_on_choose_team_pressed()`: returns if no expedition is selected; instantiates `MENU_GATE_SCENE`, sets `expedition_id` **before** adding it (so it is available in the menu's `_ready()`), connects its `closed` signal (`_on_gate_closed`, bound to the instance) and adds it to `%UI`. When the team menu closes, `_on_gate_closed` frees the instance (safe if it is already freed). The sites are **not** switched off while the team menu is open (`set_interactive` is not called): the full screen team menu is expected to swallow the clicks **[U]**.
* Closing: **Esc** closes the team menu first, then the map (each `HubMenu` closes itself on Esc); the **Back** button closes the map.

**`ExpeditionSite`** (`@tool`, `class_name ExpeditionSite`, extends Area2D; instance `expedition_site.tscn` once per expedition)
* Scene: `Area2D` with `%Visual` (Sprite2D), `%Collision` (CollisionShape2D) and `%NameLabel` (Label, hidden by default), unique names required. The click rectangle is rebuilt from the texture size times the sprite scale (`_apply_texture`).
* Exports: `expedition_id` (the `ExpeditionData.id` it stands for), `texture`, `label_offset` (default `(0, 60)`).
* `enum State { HIDDEN, TEASED, UNLOCKED }`. `UNLOCKED`: normal sprite, hover tint, name label on hover or selection (label shows the expedition name, plus " (done)" if completed). `TEASED`: black silhouette, label "???". `HIDDEN`: invisible and not clickable.
* Signal `selected(site)` (left click). Methods: `configure(expedition, state, completed)`, `set_selected(bool)` (enlarges the sprite by `SELECTED_SCALE = 1.1` and shows the label), `set_interactive(bool)` (disables picking while a menu is open on top). Joins the group `expedition_sites` at runtime.
* Clicks use `input_event` of the Area2D, so no `Control` above the sites may keep Mouse Filter = Stop over them (the map root and Backdrop are set to Ignore).

**Authoring a new site**: instance `expedition_site.tscn` under `ExpeditionSiteNodes`, set `expedition_id` (must exist in the expedition catalog) and `texture`, move it. Sites placed with a different scale (the test map uses `scale = (5, 5)`) scale their collision with them.

**Known issues / to do**
* **Unlock conditions are not applied**: every site is configured as `UNLOCKED`. Planned: if all of `data.unlock_conditions` are met (`is_met(GameState.profile)`) → `UNLOCKED`; otherwise `data.locked_display` gives the state (`LockedDisplay.HIDDEN` → `ExpeditionSite.State.HIDDEN`, `TEASED` → `State.TEASED`), with `data.unlock_hint` or the conditions' `describe()` as the text shown for a teased site. The two enums use the same names.
* The test map has two sites that both use `first_expedition` (the second is a placeholder until a second expedition exists).
* Temporary debug code is still in `ExpeditionSite.gd` (`print` calls in `_refresh()` and `_on_mouse_entered`, an `_unhandled_input` override printing every click): to remove when the map is validated. `menu_gate_map.gd` itself has none left.
* No Full Rect anchor call is needed on the team menu: the missing-grid symptom was the layer bug above, not its size.
* **Layer bug met during development**: the team menu was invisible (only its buttons seemed to show) because the map's `%UI` layer (10) and the Hub's menu layer (also 10) were equal. Fixed by moving the Hub menu layer to 2 (see section 0).

---

## 8. Expedition screen (`expedition.gd`, route `expedition`)

### 8.1 Scene tree to build
```
Expedition (Control, expedition.gd)
├── Background
├── Layout (VBox): Header (%TitleLabel, %GoalLabel, optional %AbandonButton) / %MapScroll (ScrollContainer) > %Map (Control, ExpeditionMap.gd) / %TeamPanel (HBox)
└── %DialogLayer (Control, full rect, Mouse Filter Stop, hidden)
	├── Dim (ColorRect)
	└── CenterContainer > PanelContainer > VBox: %DialogTitle, %DialogBody (autowrap), %DialogButtons (HBox)
```
`Expedition.tscn` was once overwritten by a copy of the Character scene; a rebuilt scene with exactly this tree (and the same uid) was delivered **[U]**. Scripts must be re-attached: `expedition.gd` on the root, `ExpeditionMap.gd` on `%Map`.

### 8.2 Behaviour
* `_ready()`: ensures a run (creates a test run if none, for F6), builds the map, enters the START node on a new run (`resolve_node`, **save**), then `_resume_node()` if the current node is unresolved.
* `ExpeditionMap`: columns from `get_depths()`, heights from `lane` (crowded columns are spread), buttons (`ExpeditionNodeButton`, states LOCKED/REACHABLE/CURRENT/VISITED) and link lines (taken / available / dim). Signal `node_chosen(node)`. Sizes itself to the graph (put it in a ScrollContainer).
* `_on_node_chosen` → `run.enter_node` (**no save**) → `_play_node`: BATTLE/BOSS → `_start_battle` (goes to the battle scene; if the route is unavailable a stub dialog with Victory/Defeat appears), CAMP → heal each hero 30% of max (`CAMP_HEAL_RATIO`, **revives downed heroes**), EVENT → stub dialog, END → `_finish(COMPLETED)`.
* `_resolve()` (guarded against double calls): gives the node's `loot` to the run, `resolve_node()`, **save**, refresh.
* Coming back from battle: `_resume_node` reads `run.battle_result`: VICTORY → `_on_battle_finished(true)` → `_resolve()`; DEFEAT → `_finish(DEFEATED)`.
* Abandon button (optional node): confirmation dialog → `_finish(ABANDONED)`. `_finish(outcome)` → `GameState.end_run(outcome == COMPLETED)` → summary (loot, completion bonus) → "Return to the hub".
* Team health labels are shown at the bottom (`%TeamPanel`).

---

## 9. Main menu (`main_menu.gd`)

Scene: `NewGameButton`, `ContinueButton`, `LoadButton`, `QuitButton` (unique names), `SavePanel` (hidden) > ScrollContainer > `SaveList` (VBox), optional `MessageLabel`.
* **New game**: code-built dialog asks for a name (24 chars max, Enter validates) → `GameState.new_game(name)` → hub.
* **Continue**: loads the latest save (`GameState.latest_save_slot()`); **Load**: toggles the list, one row per save: name button, date label (local time), "Delete file" button (confirmation popup "Are you sure you want to delete this savefile ?" with **No / Yes I'm sure**, built from an `AcceptDialog` with its OK button hidden). Damaged saves appear disabled.
* After loading: `SceneManager.go_to(&"expedition" if GameState.has_run() else &"hub")`. Quit button hidden on web. First usable button grabs focus.

---

## 10. Save system

* Files in `user://saves/`: `<id>.json` (id like `save_1760000000`), `<id>.json.bak` (previous version), `<id>.json.tmp` (only during a write). A legacy `user://save.json` is imported once as "Old save".
* `SaveManager` (static): `new_slot_id()`, `write(slot, content)` (temp file → swap, old file kept as backup; adds `version` and `saved_at`), `read(slot, warn := true) -> {ok, data, error}` (falls back to the backup), `list_saves()` (newest first: `{id, ok, name, saved_at}`), `latest_slot()`, `delete(slot)`, `VERSION = 1` with a `_migrate()` hook.
* Format:
```json
{ "version": 1, "saved_at": 1760000000.0, "name": "My adventure",
  "profile": { "unlocked_heroes": ["knight"], "resources": {"wood": 6}, "unlocked_locations": ["gate","carpentry"], "upgrade_levels": {"gate":1,"carpentry":1}, "completed_expeditions": ["first_expedition"] },
  "run": null  /* or { "expedition_id", "team", "hero_health", "current_node_id", "visited_nodes", "node_resolved", "battle_result", "loot" } */ }
```
* `SaveUtils`: `to_strings`, `to_names`, `dict_to_json`, `int_dict_from_json`.
* **Save moments:** `new_game`, hub `_ready`, expedition start, `_resolve()` (after each node), `end_run`, `upgrade_building`, manual save (pause menu). **Never mid-battle.** Saving is disabled while `can_save` is false (scene run alone).
* A saved run is dropped (with an explicit warning) if its expedition, a hero or its node no longer exists.

---

## 11. Editor tools (EditorScripts, run with File > Run)

* `tools/make_test_expedition.gd`: builds `data/expeditions/test_expedition.tres` (start → fight_1 → {fight_hard | camp} → fight_2 → boss → end, with loot and `completion_bonus`) and registers it in `data/expedition_catalog.tres`. Needs `res://data/character/enemies/goblin.tres`. Id: `first_expedition`.
* `tools/make_test_buildings.gd`: creates `data/buildings/{gate,carpentry,tavern,forge}.tres` + `data/building_catalog.tres` (gate and carpentry built at start; carpentry level 2 allows the forge; tavern needs carpentry 1).
Both overwrite their outputs when re-run.

---

## 12. Pause menu (`pause_menu.gd`) [T]

**Autoload scene** (Project Settings > Globals > Autoload, name `PauseMenu`, point it at `pause_menu.tscn`, loaded after `SceneManager` and `GameState`).
Scene tree:
```
PauseMenu (CanvasLayer, pause_menu.gd)            layer is set to 50 by the script
└── Root (Control, full rect, Mouse Filter = Stop)
	├── Dim (ColorRect, full rect, black ~60% alpha)
	└── CenterContainer (full rect) > PanelContainer > VBoxContainer
		├── TitleLabel (text "Pause")
		├── ResumeButton   (optional, unique name)
		├── SaveButton     (unique name)
		├── MainMenuButton (unique name)
		└── QuitButton     (unique name)
```
Behaviour:
* **Esc (`ui_cancel`)** opens/closes it (`process_mode = ALWAYS`, `get_tree().paused = true` while open). Only if: a current scene exists, the scene path is not the main menu route, `SceneManager.is_changing()` is false, the tree is not already paused.
* **Save** → `GameState.save_game()`; the button text shows "Saved!" or "Nothing to save" for 1.5 s. **Disabled in the battle scene** (detected by scene path == `ROUTES[&"battle"]`).
* **Main menu** and **Quit** each open a Yes/No prompt (AcceptDialog, OK button hidden, "No" left, "Yes" right; message warns that progress since the last save is lost). Yes → `close()` then `SceneManager.go_to(&"main_menu")`, or `get_tree().quit()`. Quit button hidden on web.
Integration steps (**all done**, the developer confirmed the pause menu works):
1. Create the scene and register the autoload.
2. In `battle.gd`, the enemy-turn delay must not run while paused: change `await get_tree().create_timer(ENEMY_ACTION_DELAY).timeout` to `create_timer(ENEMY_ACTION_DELAY, false)`.
3. `TargetingController._unhandled_input`: when Esc cancels a selection, call `get_viewport().set_input_as_handled()` (done in the delivered file; apply to the developer's copy). `HubMenu` already marks Esc as handled when closing.
4. `SceneManager` needs `is_changing()` (delivered).

---

## 13. Authoring workflows

* **New hero/enemy**: `CharacterData.tres` (unique `id`, team, tileset coords, `head_position`, stats, `deck` for heroes). Add heroes to `data/hero_catalog.tres`. Enemies are referenced directly by encounters.
* **New card**: `CardData.tres`; add it to a hero's `deck`. Hidden fields in the inspector depend on type and target type.
  Armor card: SUPPORT, target SELF/ALLY, one `StatusApplication` with the `armor` status. Bleed attack: `StatusApplication` (TARGET) with `bleeding`. Cleanse: ALLY target, `cleanse` with stacks 1.
* **New status**: `StatusData.tres` with an `effect`, `duration_type`, icon, and the `debuff` box if it is negative. A genuinely new behaviour needs a new `Effect` value (appended at the end) handled in `Character.apply_status` / `StatusComponent`.
* **Starting statuses on a character**: `CharacterData.starting_statuses` (status → stacks).
* **New expedition**: `ExpeditionData.tres` with nodes (ids, types, `next_nodes`, lanes, encounters, `loot`), press **Validate graph**, add it to `data/expedition_catalog.tres`.
* **New enemy action**: right click > New Resource > `EnemyAction`, pick the `kind` (the inspector shows only the fields that matter), set `damage` / `approach_distance` / `aoe_radius` / `windup_turns` / `effects`, then add it to `CharacterData.actions` of the enemy with a weight. A DEBUFF needs `damage` 0.
* **New enemy**: `CharacterData.tres` with `team = ENEMY`, stats, `actions` (weights), `tags` and `threat` for generated fights.
* **New expedition site on the gate map**: instance `expedition_site.tscn` under `ExpeditionSiteNodes` of `menu_gate_map.tscn`, set `expedition_id` and `texture` (see 7.4). The expedition must be in `data/expedition_catalog.tres`.
* **New unlock requirement**: new script extending `UnlockCondition` (see 3.6).
* **New building**: `BuildingData.tres` (+ `BuildingLevel`s) in `data/building_catalog.tres`, and a `HubLocation` with the **same id** placed in the hub scene (fixed position), with a `menu_scene` extending `HubMenu`. Hub warns in Output when one side is missing.
* **New hub menu**: scene with a script `extends HubMenu`, call `super._ready()` if overriding `_ready`, call `close()` when done.
* **New objective**: see 4.9.

---

## 14. Known limitations / technical TODO

* Status system: Bleeding (scaling), Poison (flat), Stun, Sleep, Evasion, armor, heal, cleanse, and cards that spend stacks (arcane charges, 3.3b) exist. Missing: the card UI does not show the charge bonus (`Battle.get_charge_bonus_damage` is ready for it), charges only boost damage, hover tooltips on icons, `USES` hooks other than Evasion (e.g. a vulnerability consumed on hit), dispel of buffs, partial cleanse, auto-generated card descriptions.
* A status applied to a character during its **own side's phase** decays at the end of that same phase (matters once enemies stun heroes).
* `HealthComponent` still has unused evasion code (to remove).
* **Enemy actions** (3.7, 4.6): only `ON_PLAY` effects run; a dodged hit still applies its effects; weights are not validated in the data files (a negative weight counts as 0, see 4.6); enemy intents use the unseeded global random generator.
* `EncounterData.spawn_pattern` AMBUSH/AMBUSHED not implemented; spawn positions are marker nodes.
* Movement and knockback are not clamped to the map; the TileMapLayer is decoration only.
* Camp and event nodes are simple (camp = heal 30%; event = stub dialog). The gate destination is now chosen on the gate map (7.4); unlock conditions are not applied there yet.
* Tavern (buffs) and Forge menus are not written. Hero health upgrades are a TODO in `RunState.start()`.
* Placeholder UI: text buttons for map nodes, code-built rows in lists, default font (blurry with pixel art), no audio, no settings menu. The health bar shows a number only (chunks every 10 points are planned).
* Gate map: see 7.4 (unlock conditions not evaluated, debug prints left in on purpose, second test site reuses `first_expedition`).
* Developer's local differences from the delivered files (see `PROJECT_CONTEXT.md` section 2): always ask for current files before editing `battle.gd`, `character.gd`, `CardInstance.gd`, `card_view.gd`, `main_menu.gd`, `HeroSlot.gd`, `CharacterData.gd`.

---

## 15. File index (delivered scripts)

| Area | Files |
|---|---|
| Autoloads / flow | `GameState.gd`, `SceneManager.gd`, `pause_menu.gd` |
| Persistent / run state | `PlayerProfile.gd`, `RunState.gd`, `SaveManager.gd`, `SaveUtils.gd` |
| Catalogs | `HeroCatalog.gd`, `ExpeditionCatalog.gd`, `BuildingCatalog.gd` |
| Character data & scene | `character_data.gd`, `character.gd`, `health_component.gd` |
| Cards | `card_data.gd`, `card_instance.gd`, `card_deck.gd`, `status_application.gd` |
| Statuses | `status_data.gd`, `status_component.gd` (new), `status_application.gd` |
| Battle | `battle.gd`, `BattleObjective.gd`, `KillAllObjective.gd`, `BattleUI.gd`, `Hand.gd`, `TargetingController.gd`, `TargetingOverlay.gd` |
| Enemy actions | `EnemyAction.gd`, `EnemyIntent.gd`, `IntentOverlay.gd` (created by `battle.gd`) |
| Encounters | `EncounterData.gd`, `EnemyCatalog.gd`, `EncounterGenerator.gd` (+ `tools/make_enemy_catalog.gd`, not shared) |
| Expedition | `ExpeditionNode.gd`, `ExpeditionData.gd`, `EncounterData.gd`, `ExpeditionMap.gd`, `ExpeditionNodeButton.gd`, `expedition.gd` |
| Hub | `Hub.gd`, `HubLocation.gd`, `HubMenu.gd`, `menu_gate_map.gd` (+ `.tscn`), `ExpeditionSite.gd` (+ `expedition_site.tscn`), `menu_gate.gd`, `HeroPortrait.gd`, `HeroSlot.gd`, `menu_carpentry.gd`, `ResourceBar.gd`, `BuildingData.gd`, `BuildingLevel.gd` |
| Unlock conditions | `UnlockCondition.gd`, `UnlockBuildingLevel.gd`, `UnlockCompletedExpedition.gd` |
| Menus | `main_menu.gd` |
| Editor tools | `tools/make_test_expedition.gd`, `tools/make_test_buildings.gd` |

---

## 16. Manual test checklist for what is still unverified

**Statuses (phase 8)**
1. Bleeding 3 on an enemy with `tick_damage` 1: it takes 3 damage when the enemy phase starts (ignoring armor), the icon number goes 3, 2, 1, then disappears; a kill by Bleeding can end the battle. With `tick_damage` 2: 6, then 4, then 2.
2. Stun on an enemy: it skips its next attack, then attacks normally. Stun on a hero: its cards are unplayable for one player turn, the other heroes' cards still work.
3. Cleanse on a hero with Bleeding + Stun: both disappear, buffs (Evasion) stay; cleanse on a clean hero does nothing and does not error; an AOE cleanse hits every ally in the radius.
4. Armor card: the armor bar jumps by exactly the stacks. Heal card: health rises, never above the maximum.
5. Evasion x2: one hit dodged per stack, the number on the icon goes down, no damage taken; Bleeding is not dodged. An Evasion with `TURNS` dodges everything until it expires.
6. Pausing during the enemy turn freezes the battle.

**Gate and expedition**
1. Gate: three columns fill the left panel; resizing the window keeps them filling; the pick numbers and the team slots still work; heroes with `unlocked_by_default` appear even in an old save.
2. `Expedition.tscn` rebuilt: the map, team panel and dialogs show again; the scripts are attached; a full expedition still works.

**Gate map [T]** (confirmed by the developer)
1. The gate building opens the map; Esc and the Back button close it.
2. Picking a site enables Choose Team and updates the labels; Choose Team opens the team menu **above** the map with the hero grid and team slots visible.
3. Esc in the team menu closes only the team menu; the launched expedition is the one of the selected site.

**Gate map, still to verify [U]**
1. After closing the team menu, the sites are clickable again and the selection is kept.
2. With unlock conditions applied (once implemented): locked sites are teased/hidden and show what is missing.
3. Completing an expedition (END node): `first_expedition` appears in the save's `completed_expeditions`, and its site shows " (done)" on the map. **Check who calls `PlayerProfile.complete_expedition`**: it was not found in the shared files.
4. While the team menu is open, clicking where a site is on the map does nothing (the sites are not disabled by code).

**Enemy actions (to verify against the running game)**
1. An enemy with several actions picks them in roughly the ratio of the weights; an enemy with an empty `actions` falls back to a melee attack and warns once in the Output panel.
2. Each kind: MELEE and RANGED stop at `approach_distance`; AOE shows its circle on the ground **at the planned spot** and a hero who left the circle is not hit; BUFF targets another enemy (itself only with `can_target_self`); DEBUFF with `damage = 0` applies its status without damage; HEAVY shows the wind-up count ("Heavy 1") and strikes on the following enemy phase.
3. The intent text color matches the kind; the AOE circle disappears when the action is done or the enemy dies.
4. A stunned enemy skips its turn: its intent stays and a HEAVY's wind-up does not progress.
5. Kill the hero an enemy was aiming at: the enemy keeps its action (and wind-up) on another hero, the head icon changes, and with no hero left the intent is cleared.
6. The head icon shows the target's head for single-target actions, nothing for AOE; a BUFF shows the head of the buffed enemy.
7. An action with an effect whose trigger is not `ON_PLAY` does nothing (known behaviour).

**Generated encounters (to verify)**
1. A node with `fill_with_pool` and no fixed enemies gets enemies whose total `threat` stays within the budget; the Output panel prints the line `Encounter '<id>': budget N -> ...` in a debug build.
2. Quit and reload the save, re-enter the same node: the same enemies; a new run: possibly different ones.
3. A boss in `enemies` plus `fill_with_pool`: the boss is always there and the rest fills the remaining budget and slots (the number of `%EnemySpawns` markers).

**Scaling Bleeding and Poison (to verify)**
1. `bleeding.tres` with `tick_damage` 3 and one stack: 3 damage at the start of the owner's turn; two stacks (applied by two cards): 6. An old `bleeding.tres` without the field still deals `stacks` damage.
2. `poison.tres` (effect POISON, `tick_damage` 4): 4 damage per turn with 1 stack and still 4 with 3 stacks, but it lasts 3 turns; the icon number is the turns left.
3. Both ignore armor (`bypass_armor`), are removed by Cleanse, and a kill by either ends the battle correctly.
4. The `tick_damage` and `bypass_armor` fields only show in the inspector for BLEED and POISON.

**Sleep (to verify)**
1. A sleeping enemy skips its turn (its intent stays, a HEAVY wind-up does not progress); a sleeping hero cannot play cards. Both lose one stack at the end of their side's phase.
2. Hitting a sleeping enemy removes Sleep at once (the icon disappears) and it acts on its next turn; a dodged hit (Evasion) does not wake it.
3. Bleeding or Poison ticks on a sleeper do not wake it; Cleanse removes Sleep.
4. A hit fully absorbed by armor still wakes (default); to change that, see the comment in `Character.take_hit`.

**Arcane charges (to verify)**
1. A card with a `StatusApplication` (SELF, `ON_PLAY`) giving a `NONE` + `USES` status "arcane charge": the icon appears on the hero with its stack count and never decays.
2. A card with `consume_status` = that status, `consume_amount` 0, `bonus_damage_per_stack` 2, base damage 3, and the hero holding 3 charges: each hit deals 9, the charges disappear, and with 0 charges it deals 3.
3. `consume_amount` 2 with 3 charges: it spends 2 (1 left) and deals base + 2 x bonus. With `consume_required` on, the card is greyed out with fewer than 2 charges (1 charge when `consume_amount` is 0).
4. Chain, multiple and AOE cards: charges are spent once, every target gets the same bonus. A critical hit multiplies the total.
5. A card that spends charges and also gives some: it ends with only the new ones.
6. A card with base damage 0 and a bonus still hits when charges are held, and does nothing without any.
