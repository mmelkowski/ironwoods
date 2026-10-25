# TECHNICAL DOCUMENTATION: Roguelite card-tactics game (Godot 4.4+, GDScript)

Companion of `PROJECT_CONTEXT.md` (design, decisions, collaboration rules, backlog).
This file documents **the code as delivered**: architecture, scripts, APIs, signals, scene trees to build, data model, save format, workflows.

> Status legend: **[T]** tested/confirmed by the developer, **[U]** delivered but not confirmed yet.
> **[T]**: phases 1 to 7 (hub buildings and carpentry included), the pause menu, saves, the status icon row (Evasion included) and the character UI placement/labels.
> **[U]**: Bleeding / Stun ticking, Cleanse, armor/heal cards, the gate grid fit, the rebuilt `Expedition.tscn`.

---

## 0. Conventions

* Godot **4.4+**. GDScript with static typing. Typed `Dictionary[StringName, int]` and `@export_tool_button` are used.
* **Ids are `StringName`** (`&"knight"`). They are stored as strings in JSON and converted back (`SaveUtils`).
* Data = **Resources** (`.tres`). Runtime state = `RefCounted` classes holding only ids / ints / lists (serializable).
* Scene internals are reached with **unique names** (`%Name`, "Access as Unique Name" in the editor). Scripts for UI often use `@export` slots instead; each script header lists what it needs.
* Rules live in `Battle`; UI scripts only read them and emit/connect signals.
* Autoloads: `GameState`, `SceneManager`, `PauseMenu` (no `class_name` on these scripts).
* The developer designs for **1920x1080**; the character `UI` node is scaled down (about 0.27), so pixel constants in `character.gd` are large (see 5.1).
* The developer's project layout: `scripts/{battle,cards,components,CharacterData}`, `scenes/{UI,character,battle.tscn,...}`, `data/{cards,character,TileSet,...}`, `assets/`, `addons/crt`.
  File names in the delivered code are mixed (`battle.gd`, `CardData.gd`/`card_data.gd`...). Only the `class_name` matters.

---

## 1. Architecture overview

```
 Main menu ──New/Load/Continue──► Hub ──Gate menu (team)──► Expedition screen ◄──► Battle scene
    ▲                              │ carpentry/tavern/forge        │  (graph, camp, events)     (cards, enemies)
    │                              ▼                               ▼
    └──────── Pause menu ◄── (available everywhere except main menu)    end of run ─► loot into profile ─► Hub

 Autoloads:  SceneManager (route + fade)   GameState (profile, run, catalogs, saves)   PauseMenu (Esc)
 Persistent: PlayerProfile (heroes, resources, buildings)     Temporary: RunState (team, health, node, loot)
 Data:       HeroCatalog / ExpeditionCatalog / BuildingCatalog  (.tres, validated at startup)
```

Flow of one expedition: `menu_gate.launch()` → `GameState.start_run()` → `SceneManager.go_to(&"expedition")` →
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
Fields: `unlocked_heroes: Array[StringName]`, `resources: Dictionary` (id → int), `unlocked_locations: Array[StringName]`, `upgrade_levels: Dictionary` (building id → level).
Signals: `resources_changed`, `locations_changed`.
Methods: `unlock_hero`, `is_hero_unlocked`, `get_resource`, `add_resource`, `can_afford(cost)`, `spend(cost) -> bool`, `unlock_location`, `is_location_unlocked`, `get_upgrade_level`, `set_upgrade_level`, `to_dict()`, `static from_dict(d)`.
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
| `attack_damage`, `attack_range` | Enemies: **placeholder** default attack. |
Helpers: `get_sprite_texture()`, `get_head_texture(size := 16x16)` (AtlasTexture crops, clamped inside the sprite).

### 3.2 `CardData` (static card, shared) and `CardInstance` (runtime)
`@tool` script (the inspector hides irrelevant fields).
* Identity: `id`, `display_name`, `description`, `art`.
* Type & mana: `card_type` (`ATTACK`/`SUPPORT`/`MANA`), `mana_generation` (hidden for MANA), `mana_cost` (MANA only).
* Damage: `damage`, `knockback` (`NONE`/`STANDARD`/`FORCEFUL`), `critical`.
* Rules: `quick`.
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
| `effect: Effect` | `NONE, ARMOR, HEAL, EVASION, BLEED, STUN, CLEANSE`. **Append only** (saved as integers). Decides the behaviour (below). |
| `debuff: bool` | Marks a negative status so `CLEANSE` removes it. `BLEED` and `STUN` are always debuffs. |
| `duration_type: DurationType` | `TURNS` (decays at the end of the owner's side phase) or `USES` (only consumed). Hidden for instant effects. |
| `decay_per_turn` | TURNS only, default 1 (0 = never expires). |
| `bypass_armor` | BLEED only, default true (damage goes straight to health). |

What `stacks` means per effect:

| Effect | Stacks | Where it lives |
|---|---|---|
| `ARMOR` | armor points added (50 = +50 armor, 1 point = 1 hp), instant | `HealthComponent` |
| `HEAL` | health restored, instant | `HealthComponent` |
| `CLEANSE` | ignored (use 1; 0 is filtered out before the effect), removes all debuffs from the target, instant | `StatusComponent` |
| `BLEED` | damage per tick at the start of the owner's turn, then `- decay_per_turn` | `StatusComponent` |
| `STUN` | turns skipped, `- decay_per_turn` per turn | `StatusComponent` |
| `EVASION` | `USES`: each stack dodges one hit (consumed); `TURNS`: dodges every hit while it lasts | `StatusComponent` |
| `NONE` | plain marker | `StatusComponent` |

Helpers: `get_effect()` (an old resource with effect `NONE` and id `&"evasion"` still counts as EVASION), `is_value_effect()` (ARMOR/HEAL), `is_debuff()`,
`get_display_number(stacks)` (turns left = `ceil(stacks / decay_per_turn)` for expiring TURNS statuses, otherwise the stacks: the number drawn on the icon).

`StatusApplication`: `trigger` (`ON_PLAY`/`ON_KILL`), `recipient` (`TARGET`/`SELF`), `status`, `stacks`. With ON_KILL only SELF makes sense. **Stacks must be >= 1.**
Resources to author: `armor`, `heal`, `cleanse` (instant), `bleeding` (BLEED, TURNS, decay 1), `stun` (STUN, TURNS, decay 1), `evasion` (EVASION, **USES**), plus an icon each.

### 3.4 Expedition data
* `ExpeditionNode` (`@tool`): `id`, `type` (`START, BATTLE, BOSS, CAMP, EVENT, END`), `title`, `description`, `next_nodes: Array[StringName]`, `encounter` (BATTLE/BOSS), `loot: Dictionary[StringName,int]`, `lane` (-1 top … 1 bottom, map layout hint). `has_encounter()`.
* `EncounterData` (`@tool`): `enemies: Array[CharacterData]`, `objective_scene: PackedScene` (root extends `BattleObjective`; empty = kill all), `spawn_pattern` (`STANDARD, AMBUSH, AMBUSHED`; only STANDARD implemented).
* `ExpeditionData` (`@tool`): `id`, `display_name`, `description`, `goal`, `completion_bonus: Dictionary[StringName,int]`, `nodes`.
  Helpers: `get_node_by_id`, `get_start`, `get_end_nodes`, `get_next_nodes(id)`, `get_depths()` (column per node, longest path), `validate() -> Array[String]`
  (unique ids, exactly one START, ≥ 1 END, valid links, no cycle, no dead end, all reachable, battles have enemies). An inspector button "Validate graph" prints the result.
* `ExpeditionCatalog`: `expeditions`, `get_expedition(id)`, `validate()`.

### 3.5 Building data (hub)
* `BuildingLevel`: `cost: Dictionary[StringName,int]`, `description`.
* `BuildingData`: `id` (**must equal the `location_id` of its `HubLocation`**), `display_name`, `description`, `built_at_start`, `requires: Dictionary[StringName,int]` (building id → min level), `levels: Array[BuildingLevel]` (`levels[0]` = construction = level 1, then upgrades). `get_max_level()`, `get_level_data(level)` (1-based).
* `BuildingCatalog`: `buildings`, `get_building(id)`, `validate()` (empty/duplicate ids, no levels, unknown requirements).

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
`phase_changed(phase)`, `turn_started(turn)`, `actions_changed(n)`, `mana_changed(n)`, `character_clicked(character)`, `intents_changed`, `card_played(card)`, `objective_updated`, `battle_ended(victory)`.
`enum Phase { SETUP, PLAYER_TURN, RESOLVING, ENEMY_TURN, ENDED }`. Constants: `ACTIONS_PER_TURN = 3`, `CRIT_MULTIPLIER = 1.5`, `KNOCKBACK_DISTANCE` (48/96), `MOVE_TIME`, `KNOCKBACK_TIME`, `ENEMY_ACTION_DELAY = 0.4`, `PLACEMENT_*`.

### 4.3 Start-up
`_ready()`: `_start_from_run()` (inside an expedition) else `roster` (battle tested alone).
`_start_from_run()`: reads the current node's `encounter`, sets `objective` from `objective_scene` if any, builds the roster = `GameState.get_run_fighters()` + `encounter.enemies`, `_in_expedition = true`.
`start_battle(characters)`: spawns by `data.team` (ally list / enemy list), faces everyone, builds the deck from the living allies, assigns enemy targets, starts the objective, starts the player turn.
Heroes spawn with their carried-over health (`Character.setup(data, start_health)`).

### 4.4 Public API (used by UI)
`can_play_card(card)`, `get_valid_targets(card)`, `get_max_picks(card)`, `allows_repeat_picks(card)` (CHAINED), `get_pickable_targets(card, selected)`, `is_valid_selection(card, selected)`,
`get_affected_targets(card, selected)` (AOE expansion), `find_approach_position(card, from, target)`, `get_approach_positions(card, selected)` (preview of where the caster will stand),
`play_card(card, selected)` (**coroutine, `await` it**), `end_player_turn()` (coroutine), `leave_battle()`.
Fields: `allies`, `enemies` (living only), `deck` (CardDeck), `phase`, `turn`, `actions_left`, `mana`, `encounter`, `objective`.

### 4.4b `play_card` pipeline
1. Guard (`can_play_card` + `is_valid_selection`), phase `RESOLVING`.
2. Pay: one action; mana for MANA cards.
3. If target team is ENEMY: caster walks (`_approach`: face target, tween to the free approach position, face again). Chain: hop by hop (each target: walk → hit → knockback, skipping dead ones); other types: walk to the first pick, then hit all affected targets at once.
4. `_deal_damage`: per target, crit multiplier, **`Character.take_hit(amount)`** (evasion check, then armor, then health); kills detected with a "was alive" check (a chain can list a target several times).
5. `_knock_back` (survivors), `_apply_effects` (ON_PLAY SELF once, TARGET per living target; ON_KILL SELF once per kill).
6. Mana gain (non-MANA cards), Quick refund if a kill, discard, `card_played`, free dead, update facings, `_check_battle_end()`; else back to `PLAYER_TURN`.

### 4.5 Free-position search (placement)
`_find_free_position(ideal, center, mover)`: starting from the ideal spot around the target, test spots every 15° alternating sides (+15, −15, +30…); if the whole circle is blocked, grow the distance by the mover's radius (`shape.radius`), up to 4 rings; fallback to the ideal spot. Obstacles = every living character except the mover (including the target). Used by cards, previews and enemy attacks.

### 4.6 Enemy turn
Order: phase `ENEMY_TURN` → `_start_of_turn_statuses(enemies)` (Bleeding, deaths freed, battle end checked) → for each enemy `_enemy_attack` → `_end_of_turn_statuses(enemies)` → `_start_player_turn()`.
`_enemy_attack`: **a stunned enemy returns immediately (skips its turn)**; otherwise ensure `intent_target` is alive (else re-assign), walk to a free position within `attack_range`, face the target, `target.take_hit(attack_damage)`, free dead, update facings, re-assign a new random target for next turn (`_assign_target`, which also turns the enemy and emits `intents_changed`), wait `ENEMY_ACTION_DELAY` (**`create_timer(delay, false)`: frozen by the pause menu**), check the end of the battle.
Allies who die are removed from lists, hidden, their cards removed from the deck, enemies aiming at them re-target. **Inside an expedition a dead hero's health is written as 0.**

### 4.6b Status timing (player side)
`_start_player_turn()`: `turn += 1` → `_start_of_turn_statuses(allies)` (Bleeding on heroes, may kill) → `_check_battle_end()` (returns if over) → phase `PLAYER_TURN`, actions reset, draw.
`end_player_turn()`: `_end_of_turn_statuses(allies)` (decay) then the enemy turn. `can_play_card()` is false for a **stunned caster**.
Helpers: `_start_of_turn_statuses(team)` (calls `StatusComponent.start_of_turn()` on each, frees dead, updates facings), `_end_of_turn_statuses(team)` (`end_of_turn()` on each).
Known limit: a status applied to a character during **its own side's phase** also decays at the end of that same phase.

### 4.7 End of battle and expedition hand-off
`_check_battle_end()` (after every action): emits `objective_updated`; `objective.is_complete()` → victory; `allies.is_empty()` or `objective.is_failed()` → defeat.
`_end_battle` → phase `ENDED` → `_record_result(victory)`: living allies' health into the run, `run.battle_result` set → `battle_ended` signal.
`leave_battle()` (Continue button): `SceneManager.go_to(&"expedition")` or, when the battle was run alone, `reload_current_scene()`.
**No save is made in a battle.**

### 4.8 Facing
Characters are never rotated. `Character.face_towards(pos)` flips `sprite.flip_h` (art faces left). `_update_facings()`: allies → closest enemy; enemies → `intent_target` (fallback closest ally). Attackers face their real target while walking/striking.

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
Required unique names inside the UI scene: `HealthBar`, `ArmorBar`, `HealthValue`, `ArmorValue`, `IntentIcon`. Optional: `StatusIcons` (without it statuses still work but are invisible).
All generated or label Controls must use Mouse Filter = Ignore so the character stays clickable. Turn off the bars' *Show Percentage*.

Constants: `TILE_SIZE` 32, `INTENT_CUTOUT_SIZE` 16x16, `STATUS_ICON_SIZE` and `STATUS_FONT_SIZE` (pixels **before** the UI scale; developer: 80 / 40), `UI_HEIGHT_ABOVE_HEAD` (developer: 20), `CLICK_RADIUS_FACTOR`.

`setup(data, start_health := -1)`; `_apply_data()`: joins group `allies`/`enemies`, builds the AtlasTexture sprite, sets the click circle radius, `_place_ui()`, `health.initialize(max, start_health)`, `add_armor(starting_armor)`, applies every `starting_statuses` entry through `apply_status`.
Click radius: delivered formula `size.x * |sprite.scale.x| / 2 * CLICK_RADIUS_FACTOR`; **the developer uses `size.x * CLICK_RADIUS_FACTOR + 5`** (their own tweak). `shape.radius` is also the character radius used by the placement search (4.5). The circle size comes from `CharacterData.size_in_tiles`.

Signals: `clicked(character)`, `died(character)`, `statuses_changed`.
Members: `intent_target` (setter refreshes the cutout of the target's head), `status_component: StatusComponent` (created in `_ready()`, no scene node), `statuses` (read-only view of `status_component.stacks`), `health`, `sprite`, `ui`.
Methods: `apply_status(status, stacks)` (ARMOR → `health.add_armor`, HEAL → `health.heal`, CLEANSE → `status_component.remove_debuffs()`, everything else → `status_component.add`; ignores `stacks <= 0` and dead characters),
`take_hit(amount) -> int` (**the one place damage enters a character**: `status_component.try_dodge()` returns 0, else `health.take_damage(amount, false)`), `is_stunned()`, `set_highlighted(on)`, `face_towards(pos)`, `is_ally()`, `is_dead()`.

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
`add(status, amount)`, `get_stacks(status)`, `has_effect(effect)`, `is_stunned()`, `consume(status, amount := 1)` (for USES statuses),
`try_dodge() -> bool` (finds an EVASION status; USES loses one stack per dodge, TURNS does not lose any),
`remove_debuffs() -> bool` (removes every status whose `is_debuff()` is true),
`start_of_turn()` (BLEED: `health.take_damage(stacks, false, status.bypass_armor)`; stops if the owner dies),
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
└── CanvasLayer > HBoxContainer (ResourceBar.gd)   stock display
```
### 7.2 Scripts
* **`Hub`**: collects every `HubLocation` below it (group `hub_locations`), hides/shows them from the profile (`_apply_unlocks`, re-run on `profile.locations_changed`), **autosaves on open**, warns about missing buildings/locations (`_check_scene`).
  Opens the menu of a clicked location on a CanvasLayer (layer 10) and disables clicks on the town meanwhile. Signals: `location_activated(location)` (also for places with no menu), `menu_opened`, `menu_closed`. `open_menu(location)`, `is_menu_open()`.
* **`HubLocation`** (Area2D): exports `location_id` (= building id), `display_name`, `menu_scene`, `enabled`, `always_unlocked`, `visual`, `label_offset`. Hover tint + name label, click emits `activated`. `set_unlocked(bool)` (hidden and not clickable until unlocked), `set_interactive(bool)`.
* **`HubMenu`** (Control, base class of every hub menu): `signal closed`, `close()`, optional `close_button` export, closes on Esc. Subclasses calling `_ready()` must call `super._ready()`. Menu root should fill the screen with Mouse Filter = Stop.
* **`ResourceBar`** (HBoxContainer): lists owned resources ("Wood 12"), updates on `resources_changed`. `static describe(cost) -> String`.

### 7.3 Menus
* **Gate** (`menu_gate.gd`, extends HubMenu): `TEAM_SIZE = 3`, `DEFAULT_EXPEDITION_ID = &"first_expedition"` (**destination selection not implemented**).
  Exports: `hero_portrait_scene`, `hero_slot_scene`, `hero_grid` (GridContainer, 3 columns), `team_slots` (HBox, 1/3 vs 2/3 layout), `launch_button`, `close_button`, `portrait_aspect` (portrait height / width, default 1.0).
  Scene: `LeftPanel` (PanelContainer) > VBox > Label + ScrollContainer (horizontal scroll off) > `HeroGrid`; `RightPanel` > `TeamSlots` + Footer (`BackButton`, `LaunchButton`).
  **Grid fit [U]**: `_setup_grid_fit()` / `_fit_grid()` size every portrait to `(scroll width - scrollbar room - gaps) / columns` so the columns fill the left panel, re-run on the scroll container's `resized`. The portrait's inner image must scale with it (TextureRect: Ignore Size + Keep Aspect Centered; Button icon: Expand Icon).
  Left: portraits of **unlocked** heroes only (`GameState.get_unlocked_heroes()`), `HeroPortrait` (Button with `%Badge` Label, toggled look = selected, number = pick order). Right: `HeroSlot` x3 (name, full sprite, stats) that share the width equally; clicking a filled slot removes the hero. Launch enabled only with 3 heroes → `GameState.start_run` + `SceneManager.go_to(&"expedition")`.
  `HeroSlot` scene: PanelContainer > VBox > `%NameLabel`, `%SpriteRect` (TextureRect, Ignore Size + Keep Aspect Centered, expand), `%StatsLabel`
  (Health / Armor / **Statuses** from `starting_statuses` via `_format_statuses()`, "-" if none / Cards).
* **Carpentry** (`menu_carpentry.gd`, extends HubMenu) [U]: scene = Control with a close button and a VBox `%BuildingList`. Lists buildings whose requirements are met: name + level, description of the next level, cost, **Build/Upgrade** button (disabled if unaffordable). Purchase = `GameState.upgrade_building()`.
* **Tavern / Forge**: buildings exist in data (via `tools/make_test_buildings.gd`) but **their menus are not written**.

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
  "profile": { "unlocked_heroes": ["knight"], "resources": {"wood": 6}, "unlocked_locations": ["gate","carpentry"], "upgrade_levels": {"gate":1,"carpentry":1} },
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
* **New building**: `BuildingData.tres` (+ `BuildingLevel`s) in `data/building_catalog.tres`, and a `HubLocation` with the **same id** placed in the hub scene (fixed position), with a `menu_scene` extending `HubMenu`. Hub warns in Output when one side is missing.
* **New hub menu**: scene with a script `extends HubMenu`, call `super._ready()` if overriding `_ready`, call `close()` when done.
* **New objective**: see 4.9.

---

## 14. Known limitations / technical TODO

* Status system: Bleeding, Stun, Evasion, armor, heal, cleanse exist. Missing: hover tooltips on icons, `USES` hooks other than Evasion (e.g. a vulnerability consumed on hit), dispel of buffs, partial cleanse, more statuses, auto-generated card descriptions.
* A status applied to a character during its **own side's phase** decays at the end of that same phase (matters once enemies stun heroes).
* `HealthComponent` still has unused evasion code (to remove).
* Enemy attacks are a placeholder (`attack_damage`, `attack_range`); no attack patterns, enemies cannot apply statuses yet.
* `EncounterData.spawn_pattern` AMBUSH/AMBUSHED not implemented; spawn positions are marker nodes.
* Movement and knockback are not clamped to the map; the TileMapLayer is decoration only.
* Camp and event nodes are simple (camp = heal 30%; event = stub dialog). Gate has a fixed destination.
* Tavern (buffs) and Forge menus are not written. Hero health upgrades are a TODO in `RunState.start()`.
* Placeholder UI: text buttons for map nodes, code-built rows in lists, default font (blurry with pixel art), no audio, no settings menu. The health bar shows a number only (chunks every 10 points are planned).
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
| Expedition | `ExpeditionNode.gd`, `ExpeditionData.gd`, `EncounterData.gd`, `ExpeditionMap.gd`, `ExpeditionNodeButton.gd`, `expedition.gd` |
| Hub | `Hub.gd`, `HubLocation.gd`, `HubMenu.gd`, `menu_gate.gd`, `HeroPortrait.gd`, `HeroSlot.gd`, `menu_carpentry.gd`, `ResourceBar.gd`, `BuildingData.gd`, `BuildingLevel.gd` |
| Menus | `main_menu.gd` |
| Editor tools | `tools/make_test_expedition.gd`, `tools/make_test_buildings.gd` |

---

## 16. Manual test checklist for what is still unverified

**Statuses (phase 8)**
1. Bleeding 3 on an enemy: it takes 3 damage when the enemy phase starts (ignoring armor), the icon number goes 3, 2, 1, then disappears; a kill by Bleeding can end the battle.
2. Stun on an enemy: it skips its next attack, then attacks normally. Stun on a hero: its cards are unplayable for one player turn, the other heroes' cards still work.
3. Cleanse on a hero with Bleeding + Stun: both disappear, buffs (Evasion) stay; cleanse on a clean hero does nothing and does not error; an AOE cleanse hits every ally in the radius.
4. Armor card: the armor bar jumps by exactly the stacks. Heal card: health rises, never above the maximum.
5. Evasion x2: one hit dodged per stack, the number on the icon goes down, no damage taken; Bleeding is not dodged. An Evasion with `TURNS` dodges everything until it expires.
6. Pausing during the enemy turn freezes the battle.

**Gate and expedition**
1. Gate: three columns fill the left panel; resizing the window keeps them filling; the pick numbers and the team slots still work; heroes with `unlocked_by_default` appear even in an old save.
2. `Expedition.tscn` rebuilt: the map, team panel and dialogs show again; the scripts are attached; a full expedition still works.
