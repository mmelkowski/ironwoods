# TECHNICAL DOCUMENTATION: Roguelite card-tactics game (Godot 4.4+, GDScript)

Companion of `PROJECT_CONTEXT.md` (design, decisions, collaboration rules, backlog).
This file documents **the code as delivered**: architecture, scripts, APIs, signals, scene trees to build, data model, save format, workflows.

> Status legend: **[T]** tested/confirmed by the developer, **[U]** delivered but not confirmed yet.
> Phases 1 to 4 and the expedition screen are **[T]**. Save list/multi saves are in use by the developer. Phase 7 (hub buildings) and the pause menu are **[U]**.

---

## 0. Conventions

* Godot **4.4+**. GDScript with static typing. Typed `Dictionary[StringName, int]` and `@export_tool_button` are used.
* **Ids are `StringName`** (`&"knight"`). They are stored as strings in JSON and converted back (`SaveUtils`).
* Data = **Resources** (`.tres`). Runtime state = `RefCounted` classes holding only ids / ints / lists (serializable).
* Scene internals are reached with **unique names** (`%Name`, "Access as Unique Name" in the editor). Scripts for UI often use `@export` slots instead; each script header lists what it needs.
* Rules live in `Battle`; UI scripts only read them and emit/connect signals.
* Autoloads: `GameState`, `SceneManager`, `PauseMenu` (no `class_name` on these scripts).
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
| `max_health`, `starting_armor`, `starting_evasion` | |
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
* `StatusData`: `id`, `display_name`, `description`, `icon`, `duration_type` (`TURNS` = active X turns, `USES` = consumed X times).
* `StatusApplication`: `trigger` (`ON_PLAY`/`ON_KILL`), `recipient` (`TARGET`/`SELF`), `status`, `stacks`. With ON_KILL only SELF makes sense.
  Evasion is a status with id `&"evasion"`, forwarded to `HealthComponent.add_evasion`.

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

### 4.4 `play_card` pipeline
1. Guard (`can_play_card` + `is_valid_selection`), phase `RESOLVING`.
2. Pay: one action; mana for MANA cards.
3. If target team is ENEMY: caster walks (`_approach`: face target, tween to the free approach position, face again). Chain: hop by hop (each target: walk → hit → knockback, skipping dead ones); other types: walk to the first pick, then hit all affected targets at once.
4. `_deal_damage`: per target, crit multiplier, `HealthComponent.take_damage`; kills detected with a "was alive" check (a chain can list a target several times).
5. `_knock_back` (survivors), `_apply_effects` (ON_PLAY SELF once, TARGET per living target; ON_KILL SELF once per kill).
6. Mana gain (non-MANA cards), Quick refund if a kill, discard, `card_played`, free dead, update facings, `_check_battle_end()`; else back to `PLAYER_TURN`.

### 4.5 Free-position search (placement)
`_find_free_position(ideal, center, mover)`: starting from the ideal spot around the target, test spots every 15° alternating sides (+15, −15, +30…); if the whole circle is blocked, grow the distance by the mover's radius (`shape.radius`), up to 4 rings; fallback to the ideal spot. Obstacles = every living character except the mover (including the target). Used by cards, previews and enemy attacks.

### 4.6 Enemy turn
For each enemy: ensure `intent_target` is alive (else re-assign), walk to a free position within `attack_range`, face the target, `take_damage(attack_damage)`, free dead, update facings, re-assign a new random target for next turn (`_assign_target`, which also turns the enemy and emits `intents_changed`), wait `ENEMY_ACTION_DELAY`, check the end of the battle.
Allies who die are removed from lists, hidden, their cards removed from the deck, enemies aiming at them re-target. **Inside an expedition a dead hero's health is written as 0.**

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
├── %Sprite (Sprite2D, centered)
├── %UI  (instance of character_ui.tscn: HealthBar, %ArmorBar, %EvasionLabel)
├── %IntentIcon (Sprite2D, above the head, e.g. position (0, -26))
└── %ClickArea (Area2D)
	└── %ClickShape (CollisionShape2D with a CircleShape2D, "Local to Scene" enabled)
```
`setup(data, start_health := -1)`; `_apply_data()` builds the AtlasTexture sprite, sets the circle radius, `health.initialize(max, start_health)`, armor/evasion, joins group `allies`/`enemies`.
Signals: `clicked(character)`, `died(character)`, `statuses_changed`. Members: `intent_target` (setter refreshes the cutout of the target's head: `INTENT_CUTOUT_SIZE` 16x16 around `data.head_position`),
`statuses` (dict, stub), `apply_status(status, stacks)` (**stub: only Evasion works**), `set_highlighted(on)`, `face_towards(pos)`, `is_ally()`, `is_dead()`.

### 5.2 `HealthComponent` (Node)
Signals: `health_changed(current, max)`, `armor_changed`, `evasion_changed`, `damaged`, `healed`, `dodged`, `died`.
`initialize(max_hp, current_hp := -1)`, `take_damage(amount, can_be_dodged := true, bypass_armor := false) -> int` (returns health actually lost; order evasion → armor → health),
`heal`, `add_armor/remove_armor`, `add_evasion/remove_evasion`, `is_dead`, `get_health_ratio`.

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
  Exports: `hero_portrait_scene`, `hero_slot_scene`, `hero_grid` (GridContainer, 3 columns), `team_slots` (HBox, 1/3 vs 2/3 layout), `launch_button`, `close_button`.
  Left: portraits of **unlocked** heroes only (`GameState.get_unlocked_heroes()`), `HeroPortrait` (Button with `%Badge` Label, toggled look = selected, number = pick order). Right: `HeroSlot` x3 (name, full sprite, stats) that share the width equally; clicking a filled slot removes the hero. Launch enabled only with 3 heroes → `GameState.start_run` + `SceneManager.go_to(&"expedition")`.
  `HeroSlot` scene: PanelContainer > VBox > `%NameLabel`, `%SpriteRect` (TextureRect, Ignore Size + Keep Aspect Centered, expand), `%StatsLabel`.
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

## 12. Pause menu (`pause_menu.gd`) [U]

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
Integration steps still to do on the developer's side:
1. Create the scene and register the autoload.
2. In `battle.gd`, the enemy-turn delay must not run while paused: change `await get_tree().create_timer(ENEMY_ACTION_DELAY).timeout` to `create_timer(ENEMY_ACTION_DELAY, false)`.
3. `TargetingController._unhandled_input`: when Esc cancels a selection, call `get_viewport().set_input_as_handled()` (done in the delivered file; apply to the developer's copy). `HubMenu` already marks Esc as handled when closing.
4. `SceneManager` needs `is_changing()` (delivered).

---

## 13. Authoring workflows

* **New hero/enemy**: `CharacterData.tres` (unique `id`, team, tileset coords, `head_position`, stats, `deck` for heroes). Add heroes to `data/hero_catalog.tres`. Enemies are referenced directly by encounters.
* **New card**: `CardData.tres`; add it to a hero's `deck`. Hidden fields in the inspector depend on type and target type.
* **New expedition**: `ExpeditionData.tres` with nodes (ids, types, `next_nodes`, lanes, encounters, `loot`), press **Validate graph**, add it to `data/expedition_catalog.tres`.
* **New building**: `BuildingData.tres` (+ `BuildingLevel`s) in `data/building_catalog.tres`, and a `HubLocation` with the **same id** placed in the hub scene (fixed position), with a `menu_scene` extending `HubMenu`. Hub warns in Output when one side is missing.
* **New hub menu**: scene with a script `extends HubMenu`, call `super._ready()` if overriding `_ready`, call `close()` when done.
* **New objective**: see 4.9.

---

## 14. Known limitations / technical TODO

* Statuses: only Evasion works; no ticking of TURNS statuses, no Bleeding/Stun, no status icons. `Character.apply_status` is a stub.
* `CardData` has no armor/heal effects.
* Enemy attacks are a placeholder (`attack_damage`, `attack_range`); no attack patterns.
* `EncounterData.spawn_pattern` AMBUSH/AMBUSHED not implemented; spawn positions are marker nodes.
* Movement and knockback are not clamped to the map; the TileMapLayer is decoration only.
* Camp and event nodes are simple (camp = heal 30%; event = stub dialog). Gate has a fixed destination.
* Tavern (buffs) and Forge menus are not written. Hero health upgrades are a TODO in `RunState.start()`.
* Placeholder UI: text buttons for map nodes, code-built rows in lists, default font (blurry with pixel art), no audio, no settings menu.
* Developer's local differences from the delivered files (see `PROJECT_CONTEXT.md` section 2): always ask for current files before editing `battle.gd`, `character.gd`, `CardInstance.gd`, `card_view.gd`, `main_menu.gd`.

---

## 15. File index (delivered scripts)

| Area | Files |
|---|---|
| Autoloads / flow | `GameState.gd`, `SceneManager.gd`, `pause_menu.gd` |
| Persistent / run state | `PlayerProfile.gd`, `RunState.gd`, `SaveManager.gd`, `SaveUtils.gd` |
| Catalogs | `HeroCatalog.gd`, `ExpeditionCatalog.gd`, `BuildingCatalog.gd` |
| Character data & scene | `character_data.gd`, `character.gd`, `health_component.gd` |
| Cards | `card_data.gd`, `card_instance.gd`, `card_deck.gd`, `status_data.gd`, `status_application.gd` |
| Battle | `battle.gd`, `BattleObjective.gd`, `KillAllObjective.gd`, `BattleUI.gd`, `Hand.gd`, `TargetingController.gd`, `TargetingOverlay.gd` |
| Expedition | `ExpeditionNode.gd`, `ExpeditionData.gd`, `EncounterData.gd`, `ExpeditionMap.gd`, `ExpeditionNodeButton.gd`, `expedition.gd` |
| Hub | `Hub.gd`, `HubLocation.gd`, `HubMenu.gd`, `menu_gate.gd`, `HeroPortrait.gd`, `HeroSlot.gd`, `menu_carpentry.gd`, `ResourceBar.gd`, `BuildingData.gd`, `BuildingLevel.gd` |
| Menus | `main_menu.gd` |
| Editor tools | `tools/make_test_expedition.gd`, `tools/make_test_buildings.gd` |

---

## 16. Manual test checklist for what is still unverified

**Phase 7 (hub buildings)**
1. Run `make_test_buildings.gd`, re-run `make_test_expedition.gd`, place `HubLocation`s with ids `gate`, `carpentry`, `tavern`, `forge`.
2. New game: only gate and carpentry visible; no warnings in Output.
3. Carpentry lists the tavern (needs carpentry 1); the forge is hidden until carpentry is level 2.
4. Do the test expedition: loot appears in the hub `ResourceBar`; build the tavern: it appears at its position; quit + Continue: still there.
5. Load an older save: gate and carpentry are present.

**Pause menu**
1. Esc opens/closes it in the hub, expedition and battle; not in the main menu; not while a hub menu or card selection uses Esc.
2. Save works in hub/expedition, is disabled in battle. Main menu / Quit prompts: No cancels, Yes acts.
3. During the enemy turn, pausing freezes the battle (needs the `create_timer(..., false)` fix).
