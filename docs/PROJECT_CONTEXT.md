# PROJECT CONTEXT: Roguelite card-tactics game (Godot 4)

> Read this file first. It explains *what* the project is, *how the developer likes to work*,
> *which decisions were already made and why*, and *what remains to be done*.
> The code itself is described in `TECHNICAL_DOCUMENTATION.md`.

---

## 1. The project in one paragraph

A 2D **roguelite tactical card game** inspired by the gameplay of *Marvel's Midnight Suns*.
The player controls a team of **3 heroes**. Every action in battle is a **card** (attack, support or mana).
Battles are **not grid based**: heroes walk freely to their target, 2D, no physics.
Between battles the player progresses through an **expedition**, a graph (DAG) of nodes (battle, boss, camp, event, end)
where they choose their own path, Slay-the-Spire / FTL style (camps heal, **event nodes give random opportunities**: trades, rests, stories). A **hub** (the camp) is where the player
picks an expedition on the gate map and a team, builds and upgrades buildings with the resources looted during expeditions, and unlocks content.

Art: **32x32 pixel art** from a tileset. Sprites are **drawn facing left** and flipped for facing right. Not animated yet.
Engine: **Godot 4.4 or later** (the project uses typed `Dictionary[StringName, int]`, `@export_tool_button`, `.gd.uid` files).
Language: **GDScript**. The project also uses a CRT shader addon (`addons/crt`), possibly rendering inside a SubViewport.

---

## 2. How to work with this developer (IMPORTANT)

* Communicates in **English** (French locale). Wants **concise, practical** answers.
* **Do NOT start a headless Godot / run Godot in the sandbox.** Explicit request: *"Give me the code and I will do the testing."*
  Review code statically and carefully instead.
* The developer **edits their own copies** of the files, so **never assume your version is the current one**. Files arrive in `/mnt/user-data/uploads`
  (sometimes with a suffix such as `character_1.gd`, `character_6377fa.gd`: the newest upload is the current one). **Check that an uploaded file really contains what its name says**
  (an `Expedition.tscn` once turned out to contain the Character scene: it had been overwritten by a "Save Scene As" mistake, and a rebuilt scene was delivered).
  Known customizations on the developer's side:
  * `battle.gd`: `character_scene` is `@onready` instead of `@export`; `roster` export pre-filled for debugging (3 heroes + 4 goblins). Status-system changes were delivered as a full file based on their copy (`take_hit`, status ticks, stun, `create_timer(..., false)`).
  * `character.gd` (**heavily customized**, latest upload `character_6377fa.gd`): `%UI/%HealthBar`, `%UI/%ArmorBar`, `%UI/%HealthValue`, `%UI/%ArmorValue`, `%UI/%IntentIcon` (intent icon now lives inside the UI sub-scene),
	optional `%UI/%StatusIcons`. The UI is built for **1920x1080** and the `UI` node is **scaled down (about 0.27)**, so the constants are large (`STATUS_ICON_SIZE = 80`, `STATUS_FONT_SIZE = 40`, `UI_HEIGHT_ABOVE_HEAD = 20`).
	The health value label shows **only the current health** (no maximum, the bar tells the rest). Click circle: they replaced the delivered formula by `shape.radius = size.x * CLICK_RADIUS_FACTOR + 5`.
  * `CardInstance.gd` and `card_view.gd` were customized (card type shown as text with a debug color per type, attack/critical damage display; `card_view` also has the owner's head icon `%CharIcon`, a `Sprite2D` the developer placed top right, fed by `_update_char_icon()`). **Always ask for the current versions before editing these.**
  * `main_menu.gd`: "Delete file" button per save row with confirmation popup.
  * `HeroSlot.gd`: fixed for `starting_statuses` (they removed `CharacterData.starting_evasion`); a status list is now shown in the stats text.
  * `CharacterData.gd`: `starting_evasion` was **removed** and replaced by `starting_statuses: Dictionary[StatusData, int]`.
  * Prefer giving **snippets + a list of what changed** when a file might have been modified by the developer; **ask them to upload the current file** before large changes.
	When the current version is available, edit **that** version and deliver the full file (this worked well for `battle.gd`, `character.gd`, `GameState.gd`, `menu_gate.gd`).
* **For a big feature, plan first.** The developer asks for the plan (data model, flow, defaults, files needed, phases) and **approves it before any code**; when they say "only do phase 1", deliver **only** that phase. State the defaults you will take unless they object, instead of asking several questions.
* **Docs are part of the deliverable.** After a feature the developer asks to "update the technical docs / the project context": merge into the **existing** files (do not create a side file), keep the [U] / [T] legend honest, and update both documents. Patch a copy of the current file with exact-text replacements and fail loudly if an anchor is missing.
* **Match the project's code style**: GDScript files use **tabs**, static typing, `##` doc comments, one `class_name` per file, `@tool` on Resources that editor tools touch.
* The developer wants to be told **what goes in code and what must be built with nodes** in the editor (scene trees, "Access as Unique Name" nodes, exports to assign, Project Settings to change).
* Values **simplicity and reusability**, and wants the **same code path for every status** (no special cases such as the old evasion handling).
* Data is authored as **Godot `.tres` Resources**, not YAML.
* They validate each step before moving on. Unverified work should be flagged as such ([U] in the technical doc).
* Scripts are delivered as files in `/mnt/user-data/outputs` (call `present_files`), listed with a short summary of what changed, what to build in the editor and a short test checklist.
* Godot gotcha lists and recurring pitfalls are in section 7.

---

## 3. Game design (as decided)

### 3.1 Global loop
1. **Main menu**: New game (asks for a save name), Continue (latest save), Load (list of saves), Quit.
2. **Hub** (camp): clickable buildings at *fixed positions*, hidden until built. Starts with the **gate** and the **carpentry workshop**.
3. **Gate**: the gate building opens the **gate map** (pick an expedition site; sites can be locked, teased or hidden by unlock conditions), then the team menu (pick 3 heroes among the unlocked ones) launches the **expedition**.
4. **Expedition screen**: the whole graph is visible. The player picks the next node among the reachable ones.
   Nodes: START, BATTLE, BOSS, CAMP, EVENT, END. The graph is hand-authored for now (procedural generation is a possible later step). Fights can be hand-made or **generated** from the expedition's enemy tags and a threat budget; an EVENT node shows a random or fixed event (3.5).
5. **Battle**: heroes with their carried-over health vs. the enemies of the encounter. On return the expedition continues.
6. **End of expedition** (END node reached, abandoned or defeated): loot goes into the profile, back to the hub.

### 3.2 Battle rules
* Turn = player phase then enemy phase. At the start of the player phase the hand is drawn **up to 6 cards** (hand persists between turns).
  The deck is the shared pool of the decks of the heroes who fight. Discard pile is reshuffled when the draw pile is empty.
* **3 actions per turn**. A card with `quick = true` refunds its action if it kills at least one target (so more than 3 cards can be played).
* **Mana** is one pool shared by the team. Attack and support cards *generate* mana (`mana_generation`, attack 1, support 2+).
  Mana cards *cost* mana (`mana_cost`) and generate none.
* Card types: `ATTACK`, `SUPPORT`, `MANA`. Target teams: `ENEMY`, `ALLY`, `SELF`.
  Target types: `SINGLE`, `MULTIPLE` (free pick within `select_radius` of the caster), `CHAINED` (each next pick within `chain_radius`
  of the previous one, the same character can be picked several times), `AOE` (everyone of the team within `aoe_radius` of the picked target).
* Damage order per hit: **evasion** (a status, see below) → **armor** (secondary health bar, only shown if > 0) → **health**. All hits go through `Character.take_hit()`.
  A critical hit multiplies damage by 1.5 (`Battle.CRIT_MULTIPLIER`). Knockback: none / standard (48 px) / forceful (96 px).
* **Movement**: a card that targets enemies makes the caster *walk* to the closest position allowing the attack (`approach_distance`).
  `approach_angle` (optional) forces a spot around the target **relative to the direction the caster comes from** (180 = behind the target, backstab).
  If the spot overlaps another character, a search around the target finds a free one (rotate, then grow the distance by the caster radius, rotate again).
  A chain walks hop by hop through its targets.
* **Facing**: characters never rotate. Sprites are flipped horizontally. Allies face their closest enemy, enemies face their `intent_target`.
* **Statuses** (all go through `Character.apply_status`, same code path as much as possible, driven by `StatusData.effect`):
  * *Value effects* are **instant** and never stored: `ARMOR` (+N armor points, 1 point = 1 hp), `HEAL` (+N health), `CLEANSE` (removes every debuff, stacks ignored).
  * *Stored statuses* (in the character's `StatusComponent`): `BLEED` (N damage at the start of the owner's turn, ignores armor/evasion, then loses 1 stack: 3 → 3, 2, 1 damage),
	`STUN` (N turns skipped, loses 1 per turn), `EVASION` (duration `USES`: each stack dodges one hit and is consumed; duration `TURNS`: dodges every hit while it lasts), `NONE` (marker for future use).
  * `duration_type`: `TURNS` stacks decay by `decay_per_turn` at the end of the owner's side phase; `USES` stacks only go down when consumed.
  * A status is a **debuff** if `BLEED`/`STUN` or if its `debuff` box is ticked (this is what `CLEANSE` removes).
  * Timing: start of a side's phase = damage over time; during the phase a stunned hero can't play cards and a stunned enemy skips its attack; end of phase = decay.
  * Each status icon on the character shows the **turns left** (or hits left for USES) in its bottom-right corner.
  * Later statuses: `SLEEP` (like Stun, but any hit that damages the sleeper removes it), `POISON` (flat `tick_damage` per turn), scaling Bleeding (`tick_damage x stacks`), `FORM` (the **druid**'s animal forms: a card puts the caster in a form for X turns; the form swaps the sprite and gives armor / evasion / status riders on attacks / a push, depending on the animal). Some cards **spend stacks** of a status for bonus damage (barbarian rage on the caster, arcane charges on the targets).
* **Enemies**: each enemy picks a weighted **`EnemyAction`** (melee, ranged, AOE, buff, debuff, heavy attack with a wind-up) from `CharacterData.actions` and **announces it as an intent** (the target's head icon and the action name above the enemy, an AOE circle on the ground); it carries it out on its **next** turn. A character with `acts` off (totem, hostage) never takes a turn.
* **Move action**: besides cards the team has **1 move per turn**. Click a hero, then an empty spot (walk) or a character (push, aimed inside a 40 degree cone). A push into another character deals collision damage (10 same team, 30 other team, to the pushed one only). Cards with a knockback push the same way.
* **Battlefield**: characters start in random free points of **spawn zones** (`SpawnZone`, patterns STANDARD / AMBUSH / AMBUSHED choose which zones are used); **walls** are TileMapLayer tiles with the custom data `blocked = true` and stop walking, spawning and knockback.
* **Objective** (`BattleObjective`): default "defeat all enemies". Checked after every action. Delivered: **boss** (kill the character with the `BOSS` role), **destroy object** (a totem), **rescue a hostage** (kill the captors, a card frees the hostage; the hostage is on the NEUTRAL team, which cards and enemies ignore). Still to do: survive waves.
* Heroes who fall are **down (0 health)** for the rest of the expedition and sit out battles until a camp heals them.
  Defeat of all heroes in a battle ends the expedition.

### 3.3 Economy and rewards (decided)
* **No penalty for failing or abandoning**: all loot gathered is kept. **Completing** the expedition adds the expedition's `completion_bonus`.
* Loot is defined **per expedition node** (`ExpeditionNode.loot`) and given when the node is resolved.
* **Events** can also trade the loot carried by the run (never the hub stock): e.g. 2 stone for 4 wood (3.5).
* Resources (wood, stone, iron...) are spent in the hub: the **carpentry workshop** builds and upgrades buildings.
  Planned: the **tavern** (temporary expedition buffs, team selection helpers) and the **forge** (permanent upgrades / crafting items to loot or start with).

### 3.4 Saves (decided)
* **Multiple named save files**. The chosen file is the one all saves go to.
* Saves happen **only at safe moments**: hub opening, expedition start, each time the party is back on the map after a node, end of an expedition,
  buildings purchases, manual save from the pause menu (disabled during battles). **Never in the middle of a battle.**
* Quitting during a battle returns to the last map state.

---

### 3.5 Events on EVENT nodes (decided)
* An EVENT node plays a short scene: a title, a text and **a few choices**; a choice has **effects** (gain or spend loot, heal or damage the party; more kinds later) and a result text. Examples that drove the design: a lumberyard that sells 4 wood for 2 stone, a quarry that sells 4 stone for 2 wood, a clearing where the party rests (+15 health each), a fellow adventurer (story only), a merchant (phase 2).
* **Which event**: a node can carry a **fixed event** (hand-made story beat); otherwise one is **drawn at random** from the `EventCatalog`. Only events whose **tags** share a word with the expedition's `enemy_tags` can come (a clearing is "forest", it cannot happen in a catacomb); an event without tag fits everywhere. One tag vocabulary for enemies and events (spelling must match exactly: `forest`, `catacomb`, `mountain`).
* **Costs use the loot carried by the run**, never the hub stock. Loot is kept even when the expedition fails, so a trade carries no risk. A choice the party cannot pay is greyed out.
* **Every event has at least one choice without a cost** ("Leave"), so the player can never be stuck.
* **Deterministic**: the same node gives the same event during one run (draw seeded with the run and the node), like generated fights, so reloading cannot reroll it. `unique_per_run` events are not drawn twice in a run.
* **Effects apply as soon as the choice is made and the node is resolved and saved at once**, then the result is shown: a save made on the result screen can never replay the event and apply it twice.
* Healing touches living heroes only (the camp is what revives); damage cannot kill by default.
* **Phase 2, the merchant** (buy temporary upgrades or cards for the expedition) comes **after the developer's upgrade system**: it needs run-level modifiers and extra cards in the run, card ids and a card catalog, and a change to how the battle deck is built.
* Ideas not built yet: choice conditions (needs a hero, needs half health), a gamble with a seeded random outcome, an ambush (an effect that starts a battle), text tokens such as a hero's name, events with art.

---

## 4. Current status

Roadmap that was followed:

| Phase | Content | State |
|---|---|---|
| 0 | Decisions (health carry-over, defeat rule, hand-authored graphs, mid-expedition saves) | Done |
| 1 | SceneManager, PlayerProfile, RunState, GameState, HeroCatalog | Done, confirmed |
| 2 | Expedition data (Node/Data/Encounter/Catalog), DAG validation, test expedition generator | Done, confirmed |
| 3 | Expedition scene (map, node states, dialogs, camp, abandon, summary) | Done, confirmed |
| 4 | Battle integration (roster from run, encounter, health carry-over, result back to the map) | Done, confirmed |
| 5 | Main menu | Done |
| 6 | Save system, multiple named save files, load list, delete | Done, in use |
| 7 | Hub integration: buildings, fixed-position locations, carpentry menu, resource bar, loot per node | **Done, confirmed** (building and crafting buildings works) |
| - | Pause menu | **Done, confirmed** (integration finished, including the `create_timer(..., false)` fix) |
| 8 | **Status system**: `StatusComponent`, Bleeding, Stun, Evasion unified as a normal status, armor / heal / cleanse value effects, icons with turns left, `starting_statuses` | Delivered. **Confirmed by the developer:** status icon row (with Evasion), number placement, bar value labels, UI placed above the head by the bottom of the health bar, `HeroSlot` fix. **Not confirmed yet [U]:** Bleeding ticks, Stun behaviour, Cleanse, armor/heal cards, `create_timer` pause behaviour in the enemy phase |
| - | Gate menu polish: portraits fill the left panel (`portrait_aspect`), unlocked-by-default heroes are added to old saves (`_ensure_starting_heroes`) | Delivered, unconfirmed |
| - | Expedition scene rebuilt (`Expedition.tscn` had been overwritten by the Character scene) | Delivered, **[U] the developer has not said whether the expedition screen works again** |
| 9 | **Gate map and unlock conditions** (expedition sites, `UnlockCondition`s, completed expeditions saved in the profile) | **Done, confirmed** (site picking, team menu, destination reaching the run, Back, Esc) |
| 10 | **Enemy actions and intents** (`EnemyAction`, `EnemyIntent`, `IntentOverlay`) replacing the placeholder attack | **Done, confirmed** by the developer |
| 11 | **Generated encounters** (threat budget, `EnemyCatalog`, `EncounterGenerator`) | Delivered, [U] |
| 12 | **Spawn zones, walls, move action** (walk and push, collision damage) | Delivered, [U] |
| 13 | **Objectives** (boss, destroy object, rescue a hostage), roles and behaviour flags, neutral team, card push with the cone, debug expeditions (`first_expedition`, `test_objectives`, `test_catacomb`) | Delivered, [U]. A fight with an objective ran in a recent session; see the fix below |
| 14 | **Statuses and druid**: Sleep, Poison, scaling Bleeding, spending stacks (rage, arcane charges), **animal forms** | Delivered, [U] |
| 15 | **Events, phase 1** (`EventData`, choices, effects, catalog, generator, code-built `EventDialog`, `tools/make_events.gd`) | Delivered in `/mnt/user-data/outputs/events/`, **[U] not run yet** |
| - | **Card owner icon**: the head of the card's hero in `%CharIcon` on each card (`card_view.gd`) | Delivered, [U] |
| - | **Fix**: `KillRoleObjective._alive_count()` crashed on a freed target (`has` on a typed array); now checks `is_instance_valid` | Delivered, [U] (reported by the developer, found while playing the Enrage card) |

**Opened loose ends:**
* `HealthComponent` still contains its old evasion code (`evasion`, `add_evasion`, `evasion_changed`, `dodged`), now unused: the file has not been seen by the agent, ask for it to remove it (and keep any "Dodged" feedback working by emitting from `Character.take_hit`).
* Files that exist in the project but were never shared with the documentation author: `tools/make_enemy_catalog.gd`, `CardData.closest_in_range`, and the aiming input / preview of the card push (`TargetingController`, `TargetingOverlay`).
* `RescueObjective`, `BossObjective`, `DestroyObjectObjective` and any other code that keeps its own list of characters were not re-checked for the freed-instance problem (rule in section 7).
* The forest debug expeditions have no EVENT node: add one by hand to test the forest events (the debug catacomb has one).
* The event files (`events/` folder of the outputs) and the patched `RunState.gd`, `ExpeditionNode.gd`, `ExpeditionData.gd`, `Expedition.gd` must be copied into the project, then `tools/make_events.gd` run once.

---

## 5. Backlog / next steps (suggested order)

1. **Verify the [U] items** (technical doc section 16: events, card owner icon, objective fix, forms, objectives, move action, statuses, Expedition scene) and send `health_component.gd` to remove the dead evasion code. Report any Output warning.
2. **The upgrade system** (the developer's next big topic, to be designed with them: forge and/or tavern; permanent upgrades and temporary expedition buffs; hero health upgrades are a TODO in `RunState.start()`; data model for items or upgrades and how they change heroes, probably reusing `StatusData` / `starting_statuses`-like data).
3. **Events, phase 2: the merchant**, **after** the upgrade system (3.5): run-level buffs and extra cards in `RunState` (ids only, serializable), a card catalog and card ids, a change in how `Battle` builds the deck, and an `OpenShop`-style effect. Smaller event follow-ups: choice conditions, seeded gambles, an ambush effect (start a battle), more events per biome, art, an event node in the forest debug expeditions.
4. **Status follow-ups**: hover tooltip (name + description) on status icons (needs a hover test that does not block clicks), show the charge bonus on the card UI (`Battle.get_charge_bonus_damage` is ready), `USES` hooks (e.g. a vulnerability consumed on hit), `DISPEL` (remove buffs, mirror of Cleanse), partial cleanse ("remove 1 debuff"), more statuses (Weakness, Strength...), card descriptions generated from effects.
5. **Battle follow-ups**: **waves** objective (needs a public spawn function on `Battle`), a gameplay effect for AMBUSH / AMBUSHED (e.g. a free first turn), pathfinding around walls (an `AStarGrid2D` from the same tiles), the second character hit by a push is only damaged (no chain reaction), enemy intents use the unseeded random generator.
6. **Tavern** (temporary expedition buffs before launching; possibly move team selection there) and **Forge** (permanent upgrades / craftable items taken on expeditions): see item 2.
7. **Expedition content**: more expeditions and sites on the gate map (each needs its own expedition file and an `ExpeditionSite`), node icons/art, possibly procedural generation, rewards choices, hero deck editing.
8. **Visual health system** (chunks every 10 points on the health/armor bars, the developer mentioned it for later).
9. Polish: themes/fonts (default font is blurry with pixel art), animations, audio, settings menu, localization (event texts and resource names are plain strings), export testing (saves use `user://saves`), a consistent UI scaling strategy for 1920x1080.

---

## 6. Design decisions worth remembering (and why)

* **Resources (`.tres`) over YAML**: typed, editable in the inspector, git friendly.
* **Components over inheritance**: `HealthComponent` is a child node of any character.
* **`CardData` (static, shared) vs `CardInstance` (runtime copy)**: buffs (critical, bonus damage) must not leak into the shared resource.
* **Effects as an array** (`StatusApplication` with `trigger` ON_PLAY / ON_KILL and `recipient` TARGET / SELF) instead of duplicated "on kill" fields.
* **Rules live in `Battle`**, UI only reads them (`get_pickable_targets`, `is_valid_selection`, `get_affected_targets`, `get_approach_positions`),
  so the preview can never disagree with the real resolution.
* **Objectives are polled** after each action rather than reacting to events mid-attack (predictable end of battle).
* **Everything persistent or mid-run is plain data (ids, ints, lists)** so it serializes to JSON. Nodes reference each other by **id**, never by resource reference.
* **Unresolved node + `battle_result`** in `RunState`: coming back from the battle scene, the expedition screen reads the result and resolves the node.
* **Saves never touch the real files in test sessions**: `GameState.can_save` is false until a game was started from the main menu (so F6 on the hub does not overwrite a save).
* **Pause menu is an autoload scene** active in every scene except the main menu.
* **One status pipeline.** Everything goes through `Character.apply_status(status, stacks)`; `StatusData.effect` decides the behaviour. Only instant value effects (armor, heal, cleanse) act on the character at once;
  every other status (Bleeding, Stun, Evasion, markers) is stored in the character's `StatusComponent`. Evasion used to live in `HealthComponent`: it was moved so that no status needs special code.
  Hits go through `Character.take_hit()`, the single hook that asks the status component whether the hit is dodged.
* **Stacks mean one number per status** (like Slay the Spire's Poison): Bleeding stacks = damage and remaining turns at the same time (decay 1), Stun stacks = turns, Evasion stacks = dodged hits. Armor 50 means 50 points, **never** "50 turns".
  The icon shows `get_display_number()`: turns left for expiring TURNS statuses, otherwise the stacks.
* **`StatusComponent` is a Node created by code** in `Character._ready()` (no scene work needed).
* **Character UI is anchored by the bottom of its health bar**, `UI_HEIGHT_ABOVE_HEAD` pixels above `CharacterData.head_position`; the code measures real transforms so the UI scene can be scaled/rearranged freely and the intent icon/status icons stack above.
* **Roles say what a character means, flags say how it behaves.** `CharacterData.roles` (BOSS, OBJECT, CAPTOR, HOSTAGE) feed the objectives; `acts` and `can_be_moved` are independent behaviour flags. Objectives find their targets through the roles, so they are data driven.
* **Generated fights are seeded** with the run and the node (the same node gives the same enemies in one run): a reload cannot reroll a fight. Events use the same rule.
* **Events are data**: `EventData` + `EventChoice` + `EventEffect` Resources (a new effect = a new script), a catalog filtered by tags, a seeded draw. **One tag vocabulary** shared by enemies and events (the expedition's `enemy_tags`) to keep authoring light; a dedicated field can be added later.
* **Event effects are applied and saved before the result screen** (the node is resolved at once), never after Continue: otherwise a save in between would replay the event and apply it twice.
* **Dialog windows that are not worth a scene are built in code** (`EventDialog`: no `.tscn` to assemble or break, added as the last child so it covers the screen). The older confirmation dialogs still use the scene's `%DialogLayer`.
* **Run economy is the carried loot**: events spend and give `RunState.loot`, never the hub stock; loot is kept on defeat, so run-level trades carry no risk.
* Hub buildings are **placed by hand in the scene** (fixed positions, Heroes of Might and Magic style) and hidden until unlocked.

---

## 7. Godot pitfalls met in this project (avoid repeating)

* Autoload scripts (`GameState`, `SceneManager`, `PauseMenu`) must **not** declare a `class_name` equal to the autoload name.
* Duplicate `class_name` files cause *"Class X hides a global script class"* and make the script invalid (this happened once because of a duplicated file).
* `EditorScript` generators: only **`@tool`** scripts can have methods called in the editor; non-tool resource scripts give placeholder instances
  (properties work, methods do not). That is why `ExpeditionData`, `ExpeditionNode`, `EncounterData` are `@tool` and `BuildingCatalog.validate()` is not called from the tool script.
* `event.pressed` on a base `InputEvent` cannot be type-inferred: write `var x: bool = (...)`.
* `Area2D` clicks are blocked by `Control` nodes with Mouse Filter = Stop (set full-screen HUD containers to Ignore) and need *Physics Object Picking*
  enabled on a SubViewport if the game renders inside one (CRT addon).
* `SceneTreeTimer` runs **while the tree is paused** by default: use `create_timer(t, false)` in gameplay code (pause menu).
* JSON stores `StringName` as strings and numbers as floats: `SaveUtils` converts back.
* Typed arrays: build with `append`/`append_array` when unsure (`Array.duplicate()` typing and literal conversions can bite).
* `%UI` can be a Control or a Node2D: keep it untyped (`@onready var ui = %UI`) when only `position`/`scale`/transform are needed.
* Generated `Control`s inside a character (status icons, labels) must use `mouse_filter = IGNORE` or they block clicks on the `Area2D`.
* Container sizes are only final a couple of frames after spawning: do layout-dependent placement after `await get_tree().process_frame` (twice) and re-run it on `item_rect_changed`.
* `Label` outline/size set by code must account for a **scaled UI node** (the developer's UI is scaled to ~0.27, hence the big font/icon constants).
* A formatted string with `%d` and a Dictionary argument fails silently (the `%d` stays in the text): format dictionaries yourself.
* Enums that are saved in `.tres` as integers: **append** new values at the end (`Effect.CLEANSE` was added last) so existing resources keep their meaning.
* **A freed node kept in a list breaks typed arrays.** A dead character leaves `Battle.allies` / `enemies` at once but is `queue_free`d after the action; an objective, a UI or a card that kept its own reference then holds a freed instance, and `Array[Character].has(freed)` raises *"Attempted to use 'has' an invalid (previously freed?) object instance into a 'TypedArray'"*. Check `is_instance_valid(x)` first and loop with `for x: Variant in list` (this crashed `KillRoleObjective`).
* **Typed arrays and dictionaries cannot be assigned from plain literals inside tool scripts** (and function arguments are not always converted): fill them with `.assign(untyped_array)` or a typed helper (`Dictionary[StringName, int]` returned by a function), as `tools/make_events.gd` does.
* **Draw order of `Node2D` / `Control` children follows the scene tree**: a `Sprite2D` placed above a full-rect `ColorRect` is drawn *under* it. Put overlays (the card's `%CharIcon`) **below** the artwork in the tree.
* A `Sprite2D` is **centered on its position**: a corner icon needs its position inset by half its size (a 32 px icon at y = 0.5 sticks out of the top of the card; use about y = 20).
* An `EditorScript` that runs a `@tool` script which calls a non-`@tool` script's method fails silently (placeholder instance): keep Resources that tools touch `@tool` (`EventData`, `EventChoice`, `EventEffect`, `EventCatalog`).
* A hidden `AcceptDialog` OK button + custom buttons is how the project forces **"No" left, "Yes" right** order (ConfirmationDialog order depends on the OS).

---

## 8. How the next agent should start

1. Read this file, then `TECHNICAL_DOCUMENTATION.md` (large: read it in chunks, the header lists what changed in the latest revisions). If only the paths of the uploaded files are listed, read them from `/mnt/user-data/uploads`. The technical doc is the more detailed source for what is delivered; this file holds the decisions and the plan.
2. Ask the developer which of the *Backlog* items to do, and **which of the [U] items were tested** (and the content of any Output warnings).
3. Before modifying a file listed in section 2 as customized, **ask for the current version** (and verify the upload really is that file).
4. Deliver code, a list of changed files, what to build in the editor (scene trees with unique names), and a short test checklist. Do not run Godot.
