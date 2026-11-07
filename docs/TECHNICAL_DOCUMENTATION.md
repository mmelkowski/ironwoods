# TECHNICAL DOCUMENTATION: Roguelite card-tactics game (Godot 4.4+, GDScript)

Companion of `PROJECT_CONTEXT.md` (design, decisions, collaboration rules, backlog).
This file documents **the code as delivered**: architecture, scripts, APIs, signals, scene trees to build, data model, save format, workflows.

> Status legend: **[T]** tested/confirmed by the developer, **[U]** delivered but not confirmed yet.
> **[T]**: phases 1 to 7 (hub buildings and carpentry included), the pause menu, saves, the status icon row (Evasion included) and the character UI placement/labels.
> **[U]**: Bleeding / Stun ticking, Cleanse, armor/heal cards, the gate grid fit, the rebuilt `Expedition.tscn`.
> **[T] added in an earlier revision**: the gate map (expedition selection before the team selection): site picking, Choose Team, destination reaching the run, Back button, Esc closing the gate, Hub menu layer.
> **[U] added in an earlier revision**: spawn zones (4.5b), walls on the TileMapLayer (4.5c) and the move action (4.5d, 6).
> **[U] added in this revision**: the objectives (boss, destroy object, rescue a hostage, 4.9), character roles and behaviour flags (3.1), the neutral team (4.3), object-only spawn zones (4.5b), the card push with the cone (4.5e), and the debug expedition generator (11).
> **[D]** = exists in the project but its file was not shared with the documentation author (now only `tools/make_enemy_catalog.gd` and `CardData.closest_in_range`, which `battle.gd` calls).

**Changes in this revision (objectives, hostage, debug expeditions)** [U]
* **Objectives** (4.9): `BattleObjective` gets the hook `on_character_died(character)`. New `KillRoleObjective` (win when the enemies that have a given role are dead) with two thin subclasses, `BossObjective` (`Role.BOSS`) and `DestroyObjectObjective` (`Role.OBJECT`), and `RescueObjective` (kill the captors, a card frees the hostage). All are data driven: they find their targets through `CharacterData.roles`.
* **Roles and behaviour** (3.1): `CharacterData.Role { BOSS, OBJECT, CAPTOR, HOSTAGE }` + `roles`, and two behaviour flags, `acts` (takes a turn) and `can_be_moved` (pushes and knockbacks move it). A totem is `OBJECT` + `acts` off + `can_be_moved` off.
* **Neutral team** (4.3, 4.5, 4.5d): `CharacterData.Team.NEUTRAL` and `Battle.neutrals`. A neutral (the hostage) is in neither `allies` nor `enemies`: cards, enemies, clicks and the defeat check ignore it, but it blocks movement and spawning.
* **Object-only spawn zones** (4.5b): `SpawnZone.objects_only`; characters with `acts` off use these zones first.
* **Card push with the cone** (4.5e): a one-target card with a knockback pushes inside the same 40 degree cone as the move action, aimed with the mouse (`plan_card_push`, `has_push_aim`, `play_card(..., aim)`).
* **`CardDeck.add_to_hand(card)`** (4.10): a card given by an objective.
* **Editor tools** (11): `tools/make_test_expedition.gd` now builds three fixed debug expeditions (`first_expedition`, `test_objectives`, `test_catacomb`) through the new shared `tools/expedition_test_kit.gd`; `tools/make_test_location.gd` keeps the locked-location tests.

**Changes in the previous revisions**
* New **gate map** (section 7.4): the gate building now opens `menu_gate_map`, where the player picks an expedition on a map of `ExpeditionSite`s, then `menu_gate` for the team.
* New `ExpeditionSite` (Area2D), `expedition_site.tscn` and the **unlock conditions** (`UnlockCondition` and subclasses, section 3.6). `ExpeditionData` has the matching `unlock_conditions` / `locked_display` / `unlock_hint` (3.4) and `PlayerProfile` the `completed_expeditions` list (2.3, saved). The conditions are defined but **not applied yet** by the gate map.
* `ExpeditionData` also has enemy tags and a threat budget for generated fights (3.4).
* `menu_gate.gd`: the destination is now `expedition_id` (set by the opener), no longer a constant. `title_label` export added.
* `Hub.gd`: menus are opened on a dedicated `CanvasLayer` at **layer 2** (see the layer convention in section 0).
* **Enemy actions and intents** (3.7, 4.6): enemies pick weighted `EnemyAction`s (melee, ranged, AOE, buff, debuff, heavy with wind-up), announce them as an `EnemyIntent` (head icon + name above the enemy, AOE circle on the ground), and carry them out on their next turn. Documented from `EnemyAction`, `EnemyIntent`, `IntentOverlay`, `CharacterData`, `character.gd` and `battle.gd`.
* **Cards that spend a status** (charges, 3.2 / 3.3b / 4.4b): `CardData.consume_status`, `consume_from` (`CASTER` = the caster's own stacks, e.g. a barbarian's rage; `TARGET` = each target's stacks, e.g. arcane charges put on enemies), `consume_amount`, `bonus_damage_per_stack`, `consume_required`; `Battle.get_charges_to_spend(card, target)` / `get_charge_bonus_damage(card, target)`.
* **Statuses: Sleep** (3.3): like Stun, but any hit that damages the sleeper removes it (`Character.take_hit` → `StatusComponent.wake_up`). `Battle` now checks `is_incapacitated()` instead of `is_stunned()`.
* **Statuses: scaling Bleeding and Poison** (3.3, 5.3): `StatusData.tick_damage`; Bleeding now deals `tick_damage x stacks`, a new `POISON` effect deals a flat `tick_damage`; `StatusComponent.consume_all` added for stacks spent by cards (arcane charges, planned, 3.3b).
* **Generated encounters** (3.8): `EncounterData.fill_with_pool`, `EnemyCatalog` and `EncounterGenerator` build a fight from the expedition's enemy tags and a threat budget.
* **Spawn zones** (4.5b): `%AllySpawns` / `%EnemySpawns` now hold `SpawnZone` areas (one or more per `SpawnPattern`) instead of fixed markers; characters start at a random free point of a zone. `AMBUSH` / `AMBUSHED` are implemented as zone sets. The layout is seeded per run and node. Old `Marker2D` children still work as a fallback.
* **Walls** (4.5c): tiles with the TileSet custom data `blocked = true` (and empty cells) stop walking, spawning and knockback (`Battle.is_walkable`, `_clamp_move`).
* **Move action** (4.5d, 6): the team has `moves_left` (1 per turn, independent from cards and actions). Click a hero, then an empty spot (walk) or a character (push, with a 40 degree cone). A push into another character deals collision damage (10 same team, 30 other team, to the pushed one only). New `MovePlan`, `MoveController`, `Battle.plan_walk` / `plan_push` / `do_move`, `moves_changed` signal; `TargetingOverlay` draws cones and arrows; `BattleUI` has an optional `moves_counter`.

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
| `id`, `display_name`, `team` (`ALLY`/`ENEMY`/`NEUTRAL`) | id required for saves. `NEUTRAL` is for a hostage: it is spawned into `Battle.neutrals` (4.3). The enum is saved as integers: **append new values at the end**. |
| `unlocked_by_default` | Hero is part of a new game's roster. |
| `tileset`, `tile_coords` (in tiles), `size_in_tiles`, `head_position` (px, default (16, 8)) | Sprite cut from the tileset. |
| `max_health`, `starting_armor` | Armor is a health layer, not a status. |
| `starting_statuses: Dictionary[StatusData, int]` | Statuses applied at spawn through `Character.apply_status` (e.g. Evasion 2, Bleeding 1). Replaces the removed `starting_evasion`. |
| `deck: Array[CardData]` | Heroes: cards added to the shared pile. |
| `actions: Dictionary[EnemyAction, int]` | Enemies: what it can do on its turn, **action → weight** (higher = more often; `{goblin_stab: 3, goblin_throw: 1}` stabs 3 times out of 4). One usable action is picked at random each turn (rules in 4.6: negative weight counts as 0, all weights 0 = equal chances, a 0 next to positive weights is never picked). **No action = a basic melee attack with a warning** (replaces the removed `attack_damage` / `attack_range`). See 3.7. |
| `tags: Array[StringName]` | Enemies: where it lives ("forest", "catacombs"). It can be picked for an expedition sharing at least one of its `enemy_tags` (3.4). |
| `threat` (1 to 99) | Enemies: cost in the threat budget of a generated battle (goblin 2, hobgoblin 6...). A strong enemy never appears while the budget is lower. |
| `roles: Array[Role]` | `enum Role { BOSS, OBJECT, CAPTOR, HOSTAGE }` (append only). What the character means for the objective of its battle (4.9): `BOSS` = `BossObjective` is won by killing it, `OBJECT` = what `DestroyObjectObjective` asks to destroy, `CAPTOR` = an enemy guarding a hostage, `HOSTAGE` = the character to rescue. Empty for an ordinary character. Helper `has_role(role)`. |
| `acts` (default true) | Off: the character never takes a turn: no intent, no attack, no delay in the enemy phase, never turned by `_update_facings` (4.6). A totem, a casket, a hostage. |
| `can_be_moved` (default true) | Off: nothing moves it: walks, pushes and knockbacks skip it and a push on it is refused (4.5d). It still blocks other characters. |
Roles say what a character **means**, the two flags say how it **behaves**; they are independent (a barrel can be immovable without any objective). A destroyable object therefore needs three settings: `roles = [OBJECT]`, `acts` off, `can_be_moved` off (`DestroyObjectObjective` warns if `acts` is still on).
Helpers: `get_sprite_texture()`, `get_head_texture(size := 16x16)` (AtlasTexture crops, clamped inside the sprite).

### 3.2 `CardData` (static card, shared) and `CardInstance` (runtime)
`@tool` script (the inspector hides irrelevant fields).
* Identity: `id`, `display_name`, `description`, `art`.
* Type & mana: `card_type` (`ATTACK`/`SUPPORT`/`MANA`), `mana_generation` (hidden for MANA), `mana_cost` (MANA only).
* Damage: `damage`, `knockback` (`NONE`/`STANDARD`/`FORCEFUL`; a one-target card pushes inside the aimed 40 degree cone and a collision hurts, see 4.5e), `critical`.
* Rules: `quick`.
* Consume (all hidden except `consume_status` while it is empty): `consume_status: StatusData` (the status the card spends: effect `NONE`, duration `USES`), `consume_from: ConsumeFrom` (`CASTER` default: the stacks of the caster, spent **once for the whole card**, bonus on **every hit**; `TARGET`: **each target spends its own stacks**, bonus only on the hit on that target), `consume_amount` (at most this many stacks; 0 = all), `bonus_damage_per_stack` (added before the critical multiplier), `consume_required` (`CASTER`: the card cannot be played without `consume_amount` stacks on the caster; `TARGET`: only targets holding `consume_amount` stacks can be picked; at least 1 when `consume_amount` is 0). See 3.3b.
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
* **Charges (stack, then spend)** [U]: a charge is a status with effect `NONE` and duration `USES` (it never decays and shows its stack count). Two uses of the same mechanism, chosen by `CardData.consume_from`:
  * **Arcane charges (wizard)**: cards **put** charges **on the enemy** (`StatusApplication`, recipient `TARGET`, trigger `ON_PLAY`); other cards with `consume_from = TARGET` **spend** them. Each target hit spends its own stacks (`min(held, consume_amount)`, 0 = all) and takes `bonus_damage_per_stack x spent` extra damage **on that hit only**: in an AOE or a chain, every enemy converts its own charges. The charges are spent even if the hit is dodged. `consume_required` limits the pickable targets to those holding enough charges.
  * **Rage (barbarian)**: cards give charges to the caster (recipient `SELF`); cards with `consume_from = CASTER` spend them once and every hit gets the same bonus; the caster's spending happens before the card's own statuses, so a card can spend charges and give new ones.
  `get_charges_to_spend(card, target)` and `get_charge_bonus_damage(card, target)` are public for previews (pass the enemy under the cursor in TARGET mode); the card UI does not use them yet. A card with 0 base damage and a bonus still hits. Only damage uses the charges for now; other consumers (healing, a status consumed on hit, extra effects per charge) can reuse `get_charges_to_spend`.

### 3.4 Expedition data
* `ExpeditionNode` (`@tool`): `id`, `type` (`START, BATTLE, BOSS, CAMP, EVENT, END`), `title`, `description`, `next_nodes: Array[StringName]`, `encounter` (BATTLE/BOSS), `loot: Dictionary[StringName,int]`, `lane` (-1 top … 1 bottom, map layout hint). `has_encounter()`.
* `EncounterData` (`@tool`): `enemies: Array[CharacterData]` (always present; the whole fight when `fill_with_pool` is off), `fill_with_pool: bool` (add enemies from the expedition's pool until the threat budget is spent, see 3.8), `objective_scene: PackedScene` (root extends `BattleObjective`; empty = kill all; see 4.9 for boss, destroy object and rescue), `spawn_pattern` (`STANDARD, AMBUSH, AMBUSHED`: picks which spawn zones are used, see 4.5b).
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
**`EncounterData`** (`@tool` Resource, stored in a BATTLE/BOSS node): `enemies` (guaranteed enemies, e.g. a boss), `fill_with_pool` (add more from the pool), `objective_scene` (root extends `BattleObjective`; empty = kill all), `spawn_pattern` (`STANDARD` / `AMBUSH` / `AMBUSHED`: picks which `SpawnZone`s of the battle scene are used, see 4.5b; `AMBUSH` = the heroes ambush the enemies, `AMBUSHED` = the enemies surround the heroes). Leave `enemies` empty for a normal generated fight.

**`EnemyCatalog`** (`@tool` Resource, one file: `res://data/enemy_catalog.tres`, constant `PATH`; built by `tools/make_enemy_catalog.gd` (not shared) or filled by hand): `enemies: Array[CharacterData]`. `get_enemy(id)`, `get_pool(tags) -> Array[CharacterData]` (ENEMY team characters sharing at least one tag), `validate()` (pushes a warning per problem: empty entry, no id, duplicated id, not on the ENEMY team, `threat < 1`). Enemies used only in hand-made encounters do not have to be listed. **Bosses, totems, captors and hostages are placed by hand: keep them out of the catalog (or without tags)**, otherwise `get_pool` can pick them as ordinary escorts (a NEUTRAL character is never in the pool, the pool only takes the ENEMY team).

**`EncounterGenerator`** (RefCounted, static): `build_enemies(expedition, node, run_seed, max_enemies = DEFAULT_MAX_ENEMIES (6))`. Called by `Battle._start_from_run()` with `GameState.run.rng_seed` and `Battle._enemy_capacity()` as `max_enemies` (the sum of the `capacity` of the enemy `SpawnZone`s of the pattern; the number of markers in the old marker layout).
1. No encounter on the node: empty list. Starts with `encounter.enemies`; without `fill_with_pool` that is the result.
2. Budget = `expedition.get_budget(node)` (`base_budget + budget_per_depth * depth + node.difficulty_bonus`) minus the `threat` of the guaranteed enemies.
3. Pool = `expedition.get_enemy_pool()`. Empty pool: a warning (no enemy matches the tags), nothing added.
4. Otherwise `_fill`: random number generator seeded with `hash("%d:%s" % [run_seed, node.id])`, so **the same node gives the same enemies during one run** (reloading a save cannot reroll a fight) and runs differ. It tries `ATTEMPTS = 8` random compositions: each repeatedly picks a **uniformly random affordable enemy** (`threat <= remaining budget`) until the free slots (`max_enemies` minus guaranteed enemies) are full or nothing is affordable, and keeps the composition that spends the most budget (the first one on a tie). A strong enemy therefore never appears while the budget is below its `threat`.
5. If the result is still empty (budget below the cheapest enemy and no guaranteed enemy), the cheapest enemy of the pool is used: **never an empty battle**.
6. Debug builds print `Encounter '<node id>': budget N -> enemy ids`.
Also `load_catalog()` (loads `EnemyCatalog.PATH`, `push_error` and an empty catalog if missing or of the wrong type); `build_enemies` itself reads the pool through `ExpeditionData.get_enemy_pool()`.
Note: a hand-made fight with more enemies than the zones' capacity is allowed: the extra enemies are still placed in the least filled zone and slide to the nearest free spot if it is crowded (they no longer stack). Only the old marker layout reuses markers (`index % count`).

---

## 4. Battle (`battle.gd`, `class_name Battle`, Node2D)

### 4.1 Scene tree to build (`battle.tscn`)
```
Battle (Node2D, battle.gd)           exports: roster, objective, spawn_pattern, map_layer, empty_cells_are_walls, show_walls_debug (character_scene: the developer's copy uses @onready)
├── TileMapLayer                     the floor AND the walls: its TileSet needs a custom data layer `blocked` (bool), see 4.5c
├── TargetingOverlay (Node2D)        AFTER the TileMapLayer, BEFORE Allies/Enemies (circles drawn under sprites)
├── %Allies (Node2D)   %Enemies (Node2D)
├── %AllySpawns (Node2D) / %EnemySpawns (Node2D)   SpawnZone children (several per pattern allowed, see 4.5b); old Marker2D children still work
├── TargetingController (Node)       exports: hand, overlay (battle found through owner)
├── MoveController (Node)            exports: hand (overlay and targeting are found by themselves)
└── BattleUI (Control, BattleUI.gd)  + Hand (HBoxContainer, Hand.gd) + counters, End Turn button, panels
```
Set full-screen HUD containers to Mouse Filter = Ignore (otherwise characters and the map can't be clicked).

### 4.2 Signals
`phase_changed(phase)`, `turn_started(turn)`, `actions_changed(n)`, `mana_changed(n)`, `moves_changed(n)`, `character_clicked(character)`, `intents_changed` (an intent was planned, re-aimed or cleared: `IntentOverlay` redraws), `card_played(card)`, `objective_updated`, `battle_ended(victory)`.
`enum Phase { SETUP, PLAYER_TURN, RESOLVING, ENEMY_TURN, ENDED }`. Constants: `ACTIONS_PER_TURN = 3`, `MOVES_PER_TURN = 1`, `CRIT_MULTIPLIER = 1.5`, `KNOCKBACK_DISTANCE` (48/96), `MOVE_TIME`, `KNOCKBACK_TIME`, `ENEMY_ACTION_DELAY = 0.4`, `PLACEMENT_*`, `SPAWN_TRIES = 24`, `SPAWN_GAP = 10`, `WALL_DATA = "blocked"`, `WALL_STEP = 8`, `WALL_BODY_FACTOR = 0.5`, `WALL_BODY_SAMPLES = 8`, `PUSH_DISTANCE = 48`, `PUSH_CONE_HALF_ANGLE = PI / 9` (20 degrees), `COLLISION_DAMAGE_SAME_TEAM = 10`, `COLLISION_DAMAGE_OPPONENT = 30`, `NO_AIM = Vector2.INF` (no aim point: a card push goes straight away from the caster).

### 4.3 Start-up
`_ready()`: `_start_from_run()` (inside an expedition) else `roster` (battle tested alone).
`_ready()` first calls `_setup_walls()` (4.5c). `_start_from_run()`: reads the current node's `encounter`, sets `spawn_pattern` and `objective` from it (`objective_scene` if any), builds the roster = `GameState.get_run_fighters()` + `encounter.enemies`, `_in_expedition = true`.
`start_battle(characters)`: spawns by `data.team` (`allies` / `enemies` / `neutrals`; positions come from the spawn zones, 4.5b). A neutral is a child of `%Enemies` like the enemies, but its click area is not pickable and it never connects `clicked`, so it cannot be selected or hovered, faces everyone, builds the deck from the living allies, assigns enemy targets, starts the objective, starts the player turn.
Heroes spawn with their carried-over health (`Character.setup(data, start_health)`).

### 4.4 Public API (used by UI)
`can_play_card(card)`, `get_valid_targets(card)`, `get_max_picks(card)`, `allows_repeat_picks(card)` (CHAINED), `get_pickable_targets(card, selected)`, `is_valid_selection(card, selected)`,
`get_charges_to_spend(card, target := null)`, `get_charge_bonus_damage(card, target := null)` (stacks the card would spend now / the extra damage, for previews; `target` is needed in TARGET mode), `get_affected_targets(card, selected)` (AOE expansion), `find_approach_position(card, from, target)`, `get_approach_positions(card, selected)` (preview of where the caster will stand),
`play_card(card, selected, aim := NO_AIM)` (**coroutine, `await` it**; `aim` = the mouse position that aims a card push, 4.5e), `end_player_turn()` (coroutine), `leave_battle()`.
Card push (4.5e): `has_push_aim(card)`, `get_card_push_distance(card)`, `plan_card_push(card, target, aim, from := NO_AIM)`.
Move action (4.5d): `can_move(character)`, `get_character_at(point)`, `plan_walk(mover, spot)`, `plan_push(mover, victim, aim)` (both return a `MovePlan`), `do_move(plan)` (**coroutine, `await` it**). Walls (4.5c): `is_walkable(at, mover := null)`.
Fields: `allies`, `enemies`, `neutrals` (living only; a neutral is in neither of the other two), `deck` (CardDeck), `phase`, `turn`, `actions_left`, `moves_left`, `mana`, `encounter`, `objective`, `spawn_pattern`, `map_layer`.

### 4.4b `play_card` pipeline
1. Guard (`can_play_card` + `is_valid_selection`), phase `RESOLVING`.
2. Pay: one action; mana for MANA cards. **2b. CASTER charges** (`consume_status`, `consume_from = CASTER`): `get_charges_to_spend`, `status_component.consume`, `bonus_damage` computed once. (TARGET charges are spent in step 4.)
3. If target team is ENEMY: caster walks (`_approach`: face target, tween to the free approach position, face again). Chain: hop by hop (each target: walk → hit → knockback, skipping dead ones); other types: walk to the first pick, then hit all affected targets at once.
4. `_deal_damage(card, targets, killed, bonus)`: per target: in TARGET mode the target first spends its own charges (`target_bonus`), then `(card.damage + bonus + target_bonus)` times the crit multiplier (a hit of 0 or less is skipped), **`Character.take_hit(amount)`** (evasion check, then armor, then health); kills detected with a "was alive" check (a chain can list a target several times).
5. `_knock_back` (survivors; a one-target card pushes inside the aimed cone and a collision hurts, see 4.5e; AOE, MULTIPLE and CHAINED cards push straight away from the caster), `_apply_effects` (ON_PLAY SELF once, TARGET per living target; ON_KILL SELF once per kill).
6. Mana gain (non-MANA cards), Quick refund if a kill, discard, `card_played`, free dead, update facings, `_check_battle_end()`; else back to `PLAYER_TURN`.

### 4.5 Free-position search (placement)
`_find_free_position(ideal, center, mover)`: starting from the ideal spot around the target, test spots every 15° alternating sides (+15, −15, +30…); if the whole circle is blocked, grow the distance by the mover's radius (`shape.radius`), up to 4 rings; fallback to the ideal spot. Obstacles = every living character except the mover (including the target; allies, enemies **and neutrals**); a spot inside a wall or outside the map is rejected too (`_is_spot_free` calls `is_walkable`, 4.5c). Used by cards, previews, enemy attacks and the spawn fallback.
`_free_position_at(ideal, center, mover)` (cards and enemies) also passes the result through `_clamp_move` so a wall between the mover and the spot stops the walk early, and the approach preview matches the real move.

### 4.5b Spawn zones (`SpawnZone.gd`, `Battle._get_spawn_position`) [U]
**`SpawnZone`** (`@tool` Node2D, `class_name SpawnZone`): exports `pattern` (`EncounterData.SpawnPattern`), `size` (Vector2, centered on the node), `elliptic` (ellipse instead of rectangle), `capacity` (1 to 8: how many characters it is meant to hold), `objects_only` (enemy side only, see below). `random_point(rng)` returns a uniformly random **global** position inside it (follows the node's position, rotation and scale). It is drawn in the editor only (translucent: blue STANDARD, green AMBUSH, red AMBUSHED, **yellow = objects only**).

**Choosing the zones** (`_get_spawn_zones(is_ally, objects_only := false)`; a zone is only taken when its `objects_only` equals the argument, so the normal call never returns an object-only zone): the `SpawnZone` children of `%AllySpawns` / `%EnemySpawns` whose `pattern` equals `Battle.spawn_pattern`; a pattern with no zone on that side falls back to the STANDARD zones; no zone at all = the old `Marker2D` layout (`index % count`). Several zones per pattern and side are allowed (e.g. two enemy zones on opposite sides for AMBUSHED). `spawn_pattern` is set from the node's `EncounterData`; it is also an `@export` so a battle scene tested alone can try AMBUSH / AMBUSHED.

**Object-only zones** [U]: a `SpawnZone` with `objects_only` on (any pattern) is used only by enemy-side characters whose `acts` is off (a totem, a hostage), so the object can stand at the back of the map. `_get_spawn_position` tries these zones first for such a character and falls back to the normal enemy zones if the scene has none. Normal enemies never use them and they do not count in `_enemy_capacity()`.

**Placing a character** (`_get_spawn_position(character, is_ally, index)`, called right after `add_child` so `shape.radius` exists):
1. The zone is the **least filled** one (`_zone_fill[zone] / capacity`), so several zones share the group in proportion to their capacity.
2. Up to `SPAWN_TRIES` (24) random points of the zone are tested with `_is_spawn_spot_free`: walkable (4.5c) and at least `radius + other radius + SPAWN_GAP (10 px)` from every character already placed.
3. Still nothing: `_find_free_position(random point, zone center, character)` slides to the nearest free spot.

**Randomness** (`_seed_spawn_rng`): inside a run the generator is seeded with `hash("%d:%s:spawn" % [run.rng_seed, run.current_node_id])`, so **the same node gives the same layout** after a reload (like the generated enemies, 3.8); a battle tested alone is randomized. **`_enemy_capacity()`** = the sum of the `capacity` of the enemy zones of the pattern (the marker count in the old layout); it is the `max_enemies` given to `EncounterGenerator`.

### 4.5c Walls (TileMapLayer) [U]
* **Marking walls**: in the TileSet add a **custom data layer named `blocked`** (type `bool`), then in the TileSet editor (Paint tab, Custom Data) tick the tiles that must block. The flag is **per tile type**: every cell that uses the tile blocks.
* **Setup** (`_setup_walls`): `map_layer` (export; empty = the first `TileMapLayer` child of the battle). Without a map nothing blocks anyone; a TileSet without the `blocked` layer logs a warning. `empty_cells_are_walls` (default true): a cell with no tile is outside the map and blocks, which gives the **map bounds**. `show_walls_debug` draws the wall tiles in red above everything while playing.
* **`is_walkable(at, mover := null)`**: the cell under the point must be painted and not `blocked` (`local_to_map(to_local(point))`, so the layer's scale is handled). With a `mover` the same test is made on 8 points of a ring of radius `shape.radius * WALL_BODY_FACTOR (0.5)` around `at`, so a body cannot stand half inside a wall.
* **`_clamp_move(mover, from, to)`**: walks the straight line in `WALL_STEP` (8 px) steps and returns the last walkable point before a wall or the map edge (`to` if the way is clear; `from` if the first step is blocked).
* **Where it applies**: `_is_spot_free` and `_is_spawn_spot_free` (destinations and spawns avoid walls), `_free_position_at` (previews) and `_move_characters` (**every walk and every knockback**: a character pushed into a wall or the map edge just stops early, with no damage).
* **Limits**: no pathfinding (a hero walking toward a target behind a wall stops at the wall; the attack still resolves); the flag cannot differ between two cells of the same tile (use an alternative tile).

### 4.5d Move action (`MovePlan`, `plan_walk`, `plan_push`, `do_move`) [U]
**Resource.** The move is **team-wide**, like actions and mana, and independent from cards: `moves_left` is set to `MOVES_PER_TURN` (1) in `_start_player_turn` (`_set_moves`, signal `moves_changed(n)`) and spent by `do_move`. Cards and characters that add or regenerate moves later only need to call `_set_moves(moves_left + n)` (no helper written yet). `can_move(character)` = phase `PLAYER_TURN`, a living hero that can act (`not is_incapacitated()`), and `moves_left > 0`.

**`MovePlan`** (RefCounted, runtime only): `kind` (`WALK` / `PUSH`), `mover`, `valid`, `destination` (where the mover ends), and for a push `victim`, `axis` (unit vector mover to victim: the center of the cone), `direction` (unit vector the victim slides along), `push_end`, `collided` (the character it hits, or null), `damage_to_victim`, `damage_to_other`.

**`plan_walk(mover, spot)`**: valid if `can_move`, the spot is at least 1 px away, `_is_spot_free` (no overlap, no wall) and `_clamp_move` reaches it.

**`plan_push(mover, victim, aim)`** (`aim` = the mouse position):
1. `axis` = from the mover toward the victim. `direction` = from the victim toward `aim`, **clamped to `PUSH_CONE_HALF_ANGLE` (20 degrees) on each side of `axis`**: a 40 degree cone centered on the movement of the mover, like a billiard shot.
2. `destination` = the contact point behind the victim: `victim position - direction * (mover radius + victim radius)`.
3. The victim slides `PUSH_DISTANCE` (48 px): first limited by walls (`_clamp_move`), then by the first character it meets (`_find_push_collision`: circle against circle, the mover and the victim excluded; a character already touching in the push direction is hit at distance 0). It stops on contact.
4. Collision damage: **same team 10 to both** (`COLLISION_DAMAGE_SAME_TEAM`); **different teams 30 to the pushed one only** (`COLLISION_DAMAGE_OPPONENT`), e.g. a hero pushing an enemy into a hero. The other character is only damaged, not pushed. **A neutral (the hostage) is a solid obstacle that is never hurt**: the pushed character takes `COLLISION_DAMAGE_OPPONENT` and the neutral nothing. A character with `can_be_moved` off does not slide (`_slide_victim` returns 0 and sets no collision).
5. `valid` = `can_move`, victim alive, not the mover and `can_be_moved`, `destination` free and reachable, and the push goes somewhere (slide of at least 1 px or a collision).

**`do_move(plan)`** (coroutine): does nothing if the plan is no longer valid. Phase `RESOLVING`, `_set_moves(moves_left - 1)`. WALK: `_move_characters({mover: destination}, MOVE_TIME)`. PUSH: the mover faces the victim and walks to `destination`, then the victim slides to `push_end` (`KNOCKBACK_TIME`), then `_apply_collision`: `take_hit` on the victim and the other character, so **armor absorbs and Evasion can dodge** it. Then `_free_dead`, `_update_facings`, `_check_battle_end()`, back to `PLAYER_TURN`. A kill by collision counts like any other (objective, defeat).
Input and preview are in `MoveController` (section 6); the rules stay here.

### 4.5e Card push (`has_push_aim`, `plan_card_push`) [U]
A card with a `knockback` (`STANDARD` 48 px, `FORCEFUL` 96 px: `KNOCKBACK_DISTANCE`) pushes its target inside **the same 40 degree cone as the move action**, aimed with the mouse.
* **`has_push_aim(card)`**: true for a one-target card (not AOE, MULTIPLE or CHAINED) whose `knockback` is not `NONE`. The other cards keep the automatic push straight away from the caster, with no collision and no damage.
* **`plan_card_push(card, target, aim, from := NO_AIM) -> MovePlan`** (kind PUSH, mover = the caster, victim = the target). `from` is where the cone starts: by default where the caster will stand after its approach (`find_approach_position`, for ENEMY-team cards), otherwise its position. `_aim_push(plan, from, aim)` fills `axis` (from to victim) and `direction` (toward `aim`, clamped to `PUSH_CONE_HALF_ANGLE` on each side; the axis itself for `NO_AIM`), then `_slide_victim(plan, get_card_push_distance(card))` fills `push_end`, `collided` and the damage with the same rules as 4.5d (walls, characters, neutrals, immovable targets). `valid` = the target is alive: **a push that goes nowhere never blocks the card**.
* **Playing**: `play_card(card, selected, aim)` hands `aim` to `_knock_back`. For each surviving target it plans the push again from the caster's real position (the caster has already walked), slides the target (`_move_characters`, `KNOCKBACK_TIME`) and applies `_apply_collision(plan)` (`take_hit`: armor absorbs, Evasion can dodge).
* `_aim_push`, `_slide_victim`, `_find_push_collision` and `_apply_collision` are shared by the move action and the cards.
* The aiming input and the preview of a card push are in `TargetingController` / `TargetingOverlay`, which were not shared with the documentation author: this section is written from `battle.gd` alone.

### 4.6 Enemy turn and intents [T, reported by the developer]
**Flow.** `end_player_turn()` → `_end_of_turn_statuses(allies)` → `await _run_enemy_turn()`: phase `ENEMY_TURN` → `_start_of_turn_statuses(enemies)` (Bleeding; deaths freed; battle end checked) → for each enemy still alive (`enemies.duplicate()`): `await _enemy_act(enemy)`, `_check_battle_end()`, wait `ENEMY_ACTION_DELAY` (0.4 s, `create_timer(delay, false)`: **frozen by the pause menu**) → `_end_of_turn_statuses(enemies)` → `_start_player_turn()`.

**Characters that do not act (`CharacterData.acts` off)** [U]: `_plan_intent` returns at once for them (so they have no intent and no icon, and never fall back to the basic melee attack), `_run_enemy_turn` skips them without the `ENEMY_ACTION_DELAY`, `_enemy_act` returns, and `_update_facings` leaves them alone (their sprite never flips). Their statuses still tick (a Bleeding totem takes damage). Enemy BUFF actions can still target them (`_candidates_for` is unchanged): "shield the totem" works.

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

**When someone dies (`_on_character_died`)**: removed from `allies` / `enemies` / `neutrals`, hidden, freed later (`_dead`, `_free_dead`). A hero: its health is written as 0 in the run and its cards leave the deck. Every enemy whose `intent.target` was the fallen character calls `_retarget_intent`: **same action and same wind-up on a new random candidate**, or a full `_plan_intent` if the action has no candidate left. An AOE spot is never re-aimed. `intents_changed` is emitted (this also hides the circle of a dead enemy). Last, **`objective.on_character_died(character)`** is called if the objective has started (4.9).

**Facing**: `_update_facings()` makes allies look at the closest enemy; each enemy looks at its intent (target, or the AOE spot) when it is valid, otherwise at the closest ally.

**Display (`character.gd`)**: the `intent` setter calls `refresh_intent()`: in `%IntentIcon` a 16x16 cut (`INTENT_CUTOUT_SIZE`) of the **target's head** (`CharacterData.head_position`, clipped to its sprite; hidden for AOE or when there is no target), and in the optional `%IntentLabel` the text `intent.get_text()` ("Stab", "Heavy 1") tinted with `action.get_color()` (`self_modulate`: keep the label's own font color white). `intent_target` is now a **read-only getter** derived from `intent` (null for AOE, no intent, or a freed target). Battle calls `refresh_intent()` after changing a wind-up or a target. `IntentOverlay` (3.7) redraws on `intents_changed`.

**Design points to be aware of**
* Effects of an action other than `ON_PLAY` are silently skipped.
* A dodged hit still applies the action's status effects.
* A stunned enemy keeps its planned intent (it is only re-planned if the target disappears).
* `intents_changed` is also emitted when an intent is cleared or re-aimed (the comment in `battle.gd` still says "picked a new target").

### 4.6b Status timing (player side)
`_start_player_turn()`: `turn += 1` → `_start_of_turn_statuses(allies)` (Bleeding on heroes, may kill) → `_check_battle_end()` (returns if over) → phase `PLAYER_TURN`, actions and moves reset, draw.
`end_player_turn()`: `_end_of_turn_statuses(allies)` (decay) then the enemy turn. `can_play_card()` is false for a caster who **cannot act** (stunned or asleep: `Character.is_incapacitated()`), or when the card has `consume_required` (CASTER mode) and the caster holds too few stacks. In TARGET mode `consume_required` filters `get_pickable_targets` instead (an enemy without charges cannot be picked, and the UI gives no explanation yet).
Helpers: `_start_of_turn_statuses(team)` (calls `StatusComponent.start_of_turn()` on each, frees dead, updates facings), `_end_of_turn_statuses(team)` (`end_of_turn()` on each).
Known limit: a status applied to a character during **its own side's phase** also decays at the end of that same phase.

### 4.7 End of battle and expedition hand-off
`_check_battle_end()` (after every action): emits `objective_updated`; `objective.is_complete()` → victory; `allies.is_empty()` or `objective.is_failed()` → defeat.
`_end_battle` → phase `ENDED` → `_record_result(victory)`: living allies' health into the run, `run.battle_result` set → `battle_ended` signal.
`leave_battle()` (Continue button): `SceneManager.go_to(&"expedition")` or, when the battle was run alone, `reload_current_scene()`.
**No save is made in a battle.**

### 4.8 Facing
Characters are never rotated. `Character.face_towards(pos)` flips `sprite.flip_h` (art faces left). `_update_facings()`: allies → closest enemy; enemies → their intent (the target, or the AOE spot; fallback closest ally). Attackers face their real target while walking/striking. Characters with `acts` off and neutrals are never turned.

### 4.9 Objectives [U for boss, destroy object and rescue]
**Base.** `BattleObjective` (Node): `description`, `start(battle)`, `_on_start()`, `is_started()`, `is_complete()`, `is_failed()`, `get_progress_text()` and the hook **`on_character_died(character)`** (empty by default). `Battle._check_battle_end()` asks `is_complete()` / `is_failed()` after every action (polling); the hook is called by `Battle._on_character_died` once the character has left its team and a hero's cards have left the deck. **The hook runs in the middle of an action: change state there (give a card, spawn a wave...), never end the battle; the polling does that right after.** `KillAllObjective` is the default (created when `objective` is null, i.e. `EncounterData.objective_scene` is empty). Anything outside the objective that reads it must check `is_started()` first.

**To add an objective**: extend `BattleObjective`, make a scene with it as root (it may `@export` resources or nodes), reference it from `EncounterData.objective_scene`. A node of type BOSS does not force any objective: the objective always comes from the encounter.

**`KillRoleObjective`** (base, usable alone): `role` (`CharacterData.Role`), `verb` ("Defeat" / "Destroy"), `progress_label`, `require_all` (default on). `_on_start()` captures the enemies of `battle.enemies` that have `role` in `data.roles`, calls the hook `_on_target_found(target)` for each and sets `description = "<verb> <names>"`. `is_complete()`: no target left (a target is alive while it is in `battle.enemies`, which `Battle` updates at once, so Bleeding and collision kills count); with `require_all` off, the first dead target is enough. `get_progress_text()`: "<progress_label>: N" only when there are several targets. **Fallback**: no enemy has the role (data error) → `push_error` and the objective behaves like kill-all ("Defeat all enemies"), so a fight can never end at once or be unwinnable.
* **`BossObjective`**: role `BOSS`, "Defeat", "Bosses left". The boss is an enemy with `BOSS` in its roles, placed in `EncounterData.enemies` (escorts fill the rest of the budget with `fill_with_pool`). Killing it wins even if the escorts are alive.
* **`DestroyObjectObjective`**: role `OBJECT`, "Destroy", "Objects left". The object is a `CharacterData` on the ENEMY team with `roles = [OBJECT]`, `acts` off and `can_be_moved` off (the objective warns if `acts` is on). It is a normal target for cards, AOE, chains and statuses, and an obstacle that can be damaged by pushing an *enemy* into it (same team: 10 to both). A hero pushed into it takes 30 and the object nothing. Destroying it wins even if the boss and the escorts are alive.

**`RescueObjective`**: export `rescue_card: CardData`. The hostage is a `CharacterData` with `team = NEUTRAL`, `roles = [HOSTAGE]`, `acts` and `can_be_moved` off; the captors are enemies with `roles = [CAPTOR]` (a captor can also be a boss).
1. `_on_start()`: hostages = neutrals with `HOSTAGE`, captors = enemies with `CAPTOR`. No hostage or no `rescue_card` → `push_error` and kill-all fallback. No captor → `push_warning` and the card is given right away. Connects `battle.card_played`. HUD: "Rescue <hostage>", then "Defeat <captors still alive>".
2. `on_character_died`: when the **last captor** is dead (several captors: all of them) the card is given: `CardInstance.new(rescue_card, holder)` is added with `CardDeck.add_to_hand` (even above `MAX_HAND_SIZE`; `draw_to_full()` never discards, so it stays until played). The holder is the first hero that is not incapacitated, else the first hero (a stunned or sleeping caster cannot play it). HUD: `Play "<card name>" to free them`.
3. **If the holder dies** with the card still in hand, the deck drops it with `remove_cards_of`; the hook notices (`character == card.caster`) and gives a new card to another living hero, so the fight cannot become unwinnable.
4. `_on_card_played(card)`: playing that card sets `_rescued`; `play_card` emits `card_played` before `_check_battle_end()`, so the victory is immediate. `is_complete()` = rescued.
5. The card is an ordinary `CardData` made by hand: `card_type` SUPPORT, `target_team` SELF, **`damage` 0** (a damage left at the default 5 would hurt the caster), no knockback, no mana. It costs one action like any card. Nothing in `CardData` is special.
6. The hostage is never hurt (no targeting, no collision damage) and nothing in the code ever "frees" it visually: the battle just ends in victory.

### 4.10 `CardDeck` (RefCounted)
`draw_pile`, `hand`, `discard_pile`, `MAX_HAND_SIZE = 6`, signal `hand_changed`; `build_from(heroes)`, `draw_to_full()`, `add_to_hand(card)` (puts a card straight into the hand, even above `MAX_HAND_SIZE`, and emits `hand_changed`; used by `RescueObjective`; `Hand` rebuilds all its views on that signal), `discard(card)`, `remove_cards_of(hero)`; reshuffles discard when empty. The hand is never discarded at the end of a turn.

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
  Public: `confirm_selection()`, `cancel_selection()`, `has_selection()` (true while a card waits for its targets). It draws previews through `TargetingOverlay` (auto-found if the export is empty).
  Esc handling calls `set_input_as_handled()` so the same key does not also open the pause menu.
* **`MoveController`** (Node, `MoveController.gd`) [U]: turns clicks into `battle.do_move()`. Exports `battle` (defaults to `owner`), `hand` (selecting a card cancels the move), `overlay` and `targeting` (found automatically when empty). **Does nothing while a card is being aimed** (`TargetingController.has_selection()`), and only in `PLAYER_TURN`.
  Steps (`enum Step { IDLE, MOVER, AIM }`): **1st click** on a hero (`can_move`) selects it; **2nd click** on an empty spot = walk (if `plan_walk` is valid), on a character (ally or enemy) = chosen for a push, on the selected hero = cancel; **3rd click** (push) confirms the angle (if `plan_push` is valid). The 3rd click is separate so the player can aim with the whole mouse, without pointing at a precise part of the character's area.
  Right click goes back one step, Esc (`set_input_as_handled`) or clicking a card cancels. It also resets on any phase change and when `moves_changed` makes the hero unable to move.
  Clicks are read in `_unhandled_input` and the character under the mouse comes from `Battle.get_character_at` (geometry), not from `character_clicked` (the Area2D picking arrives after `_unhandled_input`).
  **Preview** (every frame the mouse moves): rings for the area of every character (blue allies, orange enemies); WALK: a circle the size of the hero under the mouse (green = valid, red = blocked), none while the mouse is over a character (that character is highlighted: a click chooses it); PUSH: the cone (yellow, centered on `axis`), the arrow (`direction`), the circle where the hero will stand, a ring where the victim will end, the collided character highlighted and `-N` badges with the damage. The selected hero is highlighted (`set_highlighted`).
* **`TargetingOverlay`** (Node2D): `show_preview(circles, line, badges, cones := [], arrows := [])` / `clear()`. Circles (with optional `"color"` and `"outline_only"`) and **cones** (`{apex, axis, half_angle, length, color}`) are drawn under characters, the chain line, **arrows** (`{from, to, color}`) and number badges above. Range circle (MULTIPLE around the caster, `chain_radius` around the last pick, AOE around the target) is yellow, the caster's destination circles are translucent green.
* **`BattleUI`** (Control): exports `battle`, `action_counter`, `mana_counter`, `end_turn_button`, optional `moves_counter` ("Moves: N", from `moves_changed`), optional `objective_label`, `victory_panel`, `defeat_panel`, `victory_continue`, `defeat_continue`.
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

* **`tools/expedition_test_kit.gd`** (`@tool`, `class_name ExpeditionTestKit`, static helpers, nothing to run): the single place that lists the **paths of the test assets** (constants at the top) and the helpers shared by the two expedition tools: `load_character`, `load_boss`, `check_boss` / `check_totem` / `check_captor` / `check_hostage` (warnings when a role or a flag is missing), `shared_fight(path, pattern)`, `make_fight(enemies, objective, pattern)`, `boss_objective()` / `destroy_objective()` / `rescue_objective()` (the objective scene is **loaded if its file exists, otherwise created**: a node of the class packed and saved), `make_expedition`, `add_node`, `save_expedition` (removes the old file, saves, reads it back, prints `validate()` as warnings, registers it in `data/expedition_catalog.tres`).
  Current paths: shared fights `res://data/EncounterData/{standard,ambush,ambushed}_fight.tres`; objective scenes `res://scenes/battle/objective/{boss,destroy_object,rescue}_objective.tscn`; `BOSS_PATH` hobgoblin (fallback goblin), `CATACOMB_BOSS_PATH` `res://data/character/enemies/living_armor.tres`, `TOTEM_PATH` `res://data/character/object/totem.tres`, `CAPTOR_PATH` `res://data/character/enemies/goblin_captor.tres`, `HOSTAGE_PATH` `res://data/character/neutral/hostage.tres`, `RESCUE_CARD_PATH` `res://data/cards/hostage/unlock.tres`. A missing character or card is **never replaced by something else**: the expedition that needs it is skipped with an error naming the file.
* **`tools/make_test_expedition.gd`**: builds three fixed debug expeditions (always unlocked) and registers them. Run `tools/make_enemy_catalog.gd` first. Needs `ExpeditionTestKit`.
  1. **`first_expedition`** (file `data/expeditions/test_expedition.tres`, the id the gate menu launches): default objective only (defeat all enemies), every spawn layout: `start → fight_1 (STANDARD) → {fight_hard (AMBUSHED, +3 budget) | camp} → fight_2 (AMBUSH) → boss (STANDARD) → end`. Tags `forest`.
  2. **`test_objectives`** ("Objective trials"): `start → totem (destroy) → camp_1 → prisoner (rescue: captor + hostage) → camp_2 → boss (BossObjective, hobgoblin) → end`. No defeat-all; the boss fight is last. Tags `forest`, `base_budget` 3, `budget_per_depth` 1.
  3. **`test_catacomb`** ("The Catacombs"): 16 nodes, two branches around an event, camps, all three spawn layouts, two destroy-object fights (AMBUSHED and AMBUSH), one rescue and the **Living Armor** as the BOSS node (`BossObjective`). Tags **`catacomb`** (must match the tags of the catacomb enemies exactly; the `ExpeditionData` comment says "catacombs"), `base_budget` 3, `budget_per_depth` 1. Until some catalog enemy has the tag, `validate()` warns that the pool is empty.
  The tool warns when the boss has no `BOSS` role, or has tags (it could then be picked as an escort if it is in the `EnemyCatalog`).
* **`tools/make_test_location.gd`**: the two expeditions that test the three looks of a world-map location: `hollow_crypt` (TEASED until `first_expedition` is completed) and `sunken_watchtower` (HIDDEN until the carpentry is level 2). Simple graph, generated fights (tags `forest`), boss fight with the `BossObjective`. Not for debugging objectives.
* **Each new expedition id needs an `ExpeditionSite`** on the gate map (see 7.4) to be launched from the game.
* Tool scripts cannot call methods of scripts that are not `@tool` (they are placeholders in the editor: **properties and constants work, methods do not**). `CharacterData` is such a script, so the tools read `data.roles`, never `data.has_role()`.
* `tools/make_test_buildings.gd`: creates `data/buildings/{gate,carpentry,tavern,forge}.tres` + `data/building_catalog.tres` (gate and carpentry built at start; carpentry level 2 allows the forge; tavern needs carpentry 1).
All of them overwrite their outputs when re-run.

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
* **New boss**: `CharacterData` with `roles = [BOSS]` (keep it out of the `EnemyCatalog`, or without tags), put it in `EncounterData.enemies` of a BATTLE/BOSS node and set `objective_scene` to a scene whose root is a `BossObjective` (without an objective scene the fight is plain kill-all).
* **New destroyable object** (totem, casket): `CharacterData` on the ENEMY team with `roles = [OBJECT]`, `acts` off, `can_be_moved` off, empty `tags`; in `EncounterData.enemies` with a `DestroyObjectObjective` scene. Optional: an `objects_only` `SpawnZone` at the back of the map.
* **New hostage fight**: a hostage `CharacterData` (`team = NEUTRAL`, `roles = [HOSTAGE]`, `acts` and `can_be_moved` off), a captor (`roles = [CAPTOR]`), a rescue card (`CardData`: SUPPORT, SELF, damage 0), a scene whose root is a `RescueObjective` with `rescue_card` assigned; captor and hostage go in `EncounterData.enemies`.
* **Regenerate the debug expeditions**: run `tools/make_test_expedition.gd` (and `tools/make_test_location.gd`), see 11.

---

## 14. Known limitations / technical TODO

* Status system: Bleeding (scaling), Poison (flat), Stun, Sleep, Evasion, armor, heal, cleanse, and cards that spend stacks (charges on the caster or on enemies, 3.3b) exist. Missing: the card UI does not show the charge bonus (`Battle.get_charge_bonus_damage` is ready for it), `consume_required` on a TARGET card hides the enemies without charges silently, charges only boost damage, hover tooltips on icons, `USES` hooks other than Evasion (e.g. a vulnerability consumed on hit), dispel of buffs, partial cleanse, auto-generated card descriptions.
* A status applied to a character during its **own side's phase** decays at the end of that same phase (matters once enemies stun heroes).
* `HealthComponent` still has unused evasion code (to remove).
* **Enemy actions** (3.7, 4.6): only `ON_PLAY` effects run; a dodged hit still applies its effects; weights are not validated in the data files (a negative weight counts as 0, see 4.6); enemy intents use the unseeded global random generator.
* Spawn zones (4.5b) and walls (4.5c) are new and not confirmed yet. `AMBUSH` / `AMBUSHED` only choose different zones: no gameplay effect yet (e.g. a free first turn for the ambushers).
* Walls: no pathfinding (a straight walk stops at the first wall), the `blocked` flag is per tile type, no damage when something is pushed into a wall. An `AStarGrid2D` built from the same tiles could be added if heroes must walk around walls.
* Move action (4.5d): the pool is team-wide with no helper yet to add or regenerate moves (a card or character bonus would call `_set_moves`); the second character hit by a push is only damaged, not pushed (no chain reaction); `PUSH_DISTANCE`, the cone angle and the collision damage are constants of `battle.gd`; the preview does not explain why a push is refused (the arrow turns red); no sound or animation on impact.
* Camp and event nodes are simple (camp = heal 30%; event = stub dialog). The gate destination is now chosen on the gate map (7.4); unlock conditions are not applied there yet.
* Tavern (buffs) and Forge menus are not written. Hero health upgrades are a TODO in `RunState.start()`.
* Placeholder UI: text buttons for map nodes, code-built rows in lists, default font (blurry with pixel art), no audio, no settings menu. The health bar shows a number only (chunks every 10 points are planned).
* Gate map: see 7.4 (unlock conditions not evaluated, debug prints left in on purpose, second test site reuses `first_expedition`).
* **Objectives** (4.9) are new and not confirmed yet. A destroyable object needs three settings on its data (role + `acts` off + `can_be_moved` off); only `acts` is warned about. There is no `ExpeditionData.validate()` rule checking that a node using a boss / destroy / rescue objective really contains the matching character (the objectives log an error and fall back to kill-all at runtime; a validation would need the objective classes to be `@tool`).
* **Hostage**: a neutral is invulnerable and untargetable by design (a push collision never hurts it); there is no animation or sprite change when it is freed; the captor is not placed near the hostage (spawn zones decide; use an `objects_only` zone for the hostage and a normal zone for the captor); a neutral still shows its health bar. `Team.NEUTRAL` is only handled by `Battle`: any code outside `battle.gd` that does a `match` on `CharacterData.Team` must handle the third value (`EncounterGenerator.gd` was not shared).
* **Rescue card**: it is given to one hero (not stunned if possible) and moves to another if that hero dies; the hand can hold 7 cards while it is there (the layout of `Hand` with more than `MAX_HAND_SIZE` cards was not checked); it costs one action; the objective cannot be completed by anything else than playing that card.
* **Enemy catalog**: nothing stops a boss or an object that has tags from being picked as an ordinary escort if it is listed in the `EnemyCatalog`.
* **Card push** (4.5e) is documented from `battle.gd` only; its aiming input and preview (`TargetingController`, `TargetingOverlay`) were not shared with the documentation author.
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
| Battle | `battle.gd`, `BattleObjective.gd`, `KillAllObjective.gd`, `KillRoleObjective.gd`, `BossObjective.gd`, `DestroyObjectObjective.gd`, `RescueObjective.gd`, `BattleUI.gd`, `Hand.gd`, `TargetingController.gd`, `TargetingOverlay.gd`, `SpawnZone.gd`, `MovePlan.gd`, `MoveController.gd` |
| Enemy actions | `EnemyAction.gd`, `EnemyIntent.gd`, `IntentOverlay.gd` (created by `battle.gd`) |
| Encounters | `EncounterData.gd`, `EnemyCatalog.gd`, `EncounterGenerator.gd` (+ `tools/make_enemy_catalog.gd`, not shared) |
| Expedition | `ExpeditionNode.gd`, `ExpeditionData.gd`, `EncounterData.gd`, `ExpeditionMap.gd`, `ExpeditionNodeButton.gd`, `expedition.gd` |
| Hub | `Hub.gd`, `HubLocation.gd`, `HubMenu.gd`, `menu_gate_map.gd` (+ `.tscn`), `ExpeditionSite.gd` (+ `expedition_site.tscn`), `menu_gate.gd`, `HeroPortrait.gd`, `HeroSlot.gd`, `menu_carpentry.gd`, `ResourceBar.gd`, `BuildingData.gd`, `BuildingLevel.gd` |
| Unlock conditions | `UnlockCondition.gd`, `UnlockBuildingLevel.gd`, `UnlockCompletedExpedition.gd` |
| Menus | `main_menu.gd` |
| Editor tools | `tools/expedition_test_kit.gd`, `tools/make_test_expedition.gd`, `tools/make_test_location.gd`, `tools/make_test_buildings.gd` |

---

## 16. Manual test checklist for what is still unverified

**Objectives (to verify), with the debug expeditions `test_objectives` and `test_catacomb`**
1. *Boss*: the HUD shows "Defeat <boss>"; killing a minion does not end the fight; killing the boss wins even with minions alive; a boss killed by Bleeding or a collision also wins. A BOSS fight whose boss lacks the `BOSS` role logs an error and plays as kill-all.
2. *Destroy object*: the HUD shows "Destroy <object>"; the object has no intent icon, never attacks, never moves in the enemy phase and the enemy phase has no pause for it. Clicking it with the move action gives a red arrow and spends nothing; a card with a push damages it but does not move it. Destroying it wins with the boss alive. Pushing an enemy into it deals 10 to both; a hero pushed into it takes 30 and the object nothing. If `acts` is left on, a warning appears. It appears in the yellow `objects_only` zone if the scene has one, otherwise in an enemy zone.
3. *Rescue*: the HUD shows "Rescue <hostage>" then "Defeat <captor>"; the hostage cannot be clicked or targeted, blocks walking and pushes, and is never damaged. Killing the captor (by a card, Bleeding or a collision) puts the card in a hero's hand at once, even with a full hand, and the HUD asks to play it; the card stays through end of turn; playing it wins immediately. If the holder dies first, the card moves to another hero. Removing the `HOSTAGE` role logs an error and plays as kill-all.
4. *Generator*: running `tools/make_test_expedition.gd` creates the three expeditions with no unexpected warning (missing assets are named in an error), `first_expedition` still launches from the gate, and its fights use the three layouts (`fight_1` standard, `fight_hard` ambushed, `fight_2` ambush).
5. *Catacomb*: `test_catacomb` is long (16 nodes), its fights contain `catacomb` enemies, and its last node is the Living Armor with the boss objective.
6. *Card push*: a one-target card with a knockback pushes inside the 40 degree cone toward the mouse; an AOE or chain card pushes straight away from the caster; a collision hurts like in the move action.

**Move action (to verify)**
1. `moves_counter` (if assigned) shows "Moves: 1" at the start of each player turn; after one walk or push it shows 0 and **no hero** can start another move until the next turn.
2. Click a hero, then an empty spot: green circle under the mouse (red on an occupied spot or a wall), the hero walks there on the 2nd click. Click the selected hero again, right click or Esc: cancelled with no move spent.
3. Click a hero, then another character (ally or enemy): the cone (40 degrees) centered on the line hero to target and the arrow appear; moving the mouse around the target rotates the arrow only inside the cone; the 3rd click starts the push. Right click goes back to the walk step.
4. Push an enemy into another enemy: 10 damage to both. Push an enemy into a hero: 30 to the enemy only. Push a hero into an enemy: 30 to the hero only. The `-N` badges match the damage dealt (armor and Evasion aside).
5. A push toward a wall stops at the wall with no damage; a push that cannot move at all (wall against the target, nobody hit) gives a red arrow and the 3rd click does nothing.
6. With a card selected, clicking an ally still targets the card; clicking a card while a move is in progress cancels the move. During the enemy turn or a card animation nothing can be started.
7. A stunned or sleeping hero cannot be selected; killing someone with a collision updates the objective and can end the battle.

**Statuses (phase 8)**
1. Bleeding 3 on an enemy with `tick_damage` 1: it takes 3 damage when the enemy phase starts (ignoring armor), the icon number goes 3, 2, 1, then disappears; a kill by Bleeding can end the battle. With `tick_damage` 2: 6, then 4, then 2.
2. Stun on an enemy: it skips its next attack, then attacks normally. Stun on a hero: its cards are unplayable for one player turn, the other heroes' cards still work.
3. Cleanse on a hero with Bleeding + Stun: both disappear, buffs (Evasion) stay; cleanse on a clean hero does nothing and does not error; an AOE cleanse hits every ally in the radius.
4. Armor card: the armor bar jumps by exactly the stacks. Heal card: health rises, never above the maximum.
5. Evasion x2: one hit dodged per stack, the number on the icon goes down, no damage taken; Bleeding is not dodged. An Evasion with `TURNS` dodges everything until it expires.
6. Pausing during the enemy turn freezes the battle.
