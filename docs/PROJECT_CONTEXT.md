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
where they choose their own path, Slay-the-Spire / FTL style. A **hub** (the camp) is where the player
picks a team at the gate, builds and upgrades buildings with the resources looted during expeditions, and unlocks content.

Art: **32x32 pixel art** from a tileset. Sprites are **drawn facing left** and flipped for facing right. Not animated yet.
Engine: **Godot 4.4 or later** (the project uses typed `Dictionary[StringName, int]`, `@export_tool_button`, `.gd.uid` files).
Language: **GDScript**. The project also uses a CRT shader addon (`addons/crt`), possibly rendering inside a SubViewport.

---

## 2. How to work with this developer (IMPORTANT)

* Communicates in **English** (French locale). Wants **concise, practical** answers.
* **Do NOT start a headless Godot / run Godot in the sandbox.** Explicit request: *"Give me the code and I will do the testing."*
  (Earlier in the project headless tests were used; the developer then asked to stop.) Review code statically and carefully instead.
* The developer **edits their own copies** of the files, so **never assume your version is the current one**.
  Known customizations on the developer's side:
  * `battle.gd`: `character_scene` was switched from `@export` to `@onready` (the spawn crashed otherwise); the `roster` export is
	pre-filled for debugging (3 heroes + 4 goblins).
  * `character.gd`: uses a `CircleShape2D` click shape (`shape` variable, radius set from the sprite), scene uses `%UI/HealthBar`, `%UI/%ArmorBar`, `%UI/%EvasionLabel`
	(the UI is an instanced sub-scene `character_ui.tscn`); the name label was removed.
  * `CardInstance.gd` and `card_view.gd` were customized (card type shown as text with a debug color per type,
	attack/critical damage display). **Always ask for the current versions before editing these.**
  * `main_menu.gd`: the developer added a "Delete file" button per save row (merged afterwards with a confirmation popup).
  * Prefer giving **snippets + a list of what changed** when a file might have been modified by the developer;
	**ask them to upload the current file** before large changes.
* The developer wants to be told **what goes in code and what must be built with nodes** in the editor
  (scene trees, "Access as Unique Name" nodes, exports to assign, Project Settings to change).
* Values **simplicity and reusability**. Data is authored as **Godot `.tres` Resources**, not YAML (this was explained and accepted).
* They validate each step before moving on ("Go for phase N"). Unverified work should be flagged as such.
* Scripts are delivered as files (the previous agent wrote them to `/mnt/user-data/outputs`) and listed with a short summary of what changed.
* Godot gotcha lists and recurring pitfalls are in section 7.

---

## 3. Game design (as decided)

### 3.1 Global loop
1. **Main menu**: New game (asks for a save name), Continue (latest save), Load (list of saves), Quit.
2. **Hub** (camp): clickable buildings at *fixed positions*, hidden until built. Starts with the **gate** and the **carpentry workshop**.
3. **Gate**: pick a team of 3 heroes among the unlocked ones, launch an **expedition**.
4. **Expedition screen**: the whole graph is visible. The player picks the next node among the reachable ones.
   Nodes: START, BATTLE, BOSS, CAMP, EVENT, END. The graph is hand-authored for now (procedural generation is a possible later step).
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
* Damage order per hit: **evasion** (each stack dodges one hit) → **armor** (secondary health bar, only shown if > 0) → **health**.
  A critical hit multiplies damage by 1.5 (`Battle.CRIT_MULTIPLIER`). Knockback: none / standard (48 px) / forceful (96 px).
* **Movement**: a card that targets enemies makes the caster *walk* to the closest position allowing the attack (`approach_distance`).
  `approach_angle` (optional) forces a spot around the target **relative to the direction the caster comes from** (180 = behind the target, backstab).
  If the spot overlaps another character, a search around the target finds a free one (rotate, then grow the distance by the caster radius, rotate again).
  A chain walks hop by hop through its targets.
* **Facing**: characters never rotate. Sprites are flipped horizontally. Allies face their closest enemy, enemies face their `intent_target`.
* **Enemies**: each enemy has an `intent_target` (an ally chosen at random, shown by a small cutout of that ally's head above the enemy).
  On its turn the enemy walks to it and hits with a placeholder default attack (`attack_damage`, `attack_range`), then picks the next target.
* **Objective** (`BattleObjective`): default "defeat all enemies". Checked after every action. Designed for others (boss, destroy an object,
  survive waves, rescue a hostage).
* Heroes who fall are **down (0 health)** for the rest of the expedition and sit out battles until a camp heals them.
  Defeat of all heroes in a battle ends the expedition.

### 3.3 Economy and rewards (decided)
* **No penalty for failing or abandoning**: all loot gathered is kept. **Completing** the expedition adds the expedition's `completion_bonus`.
* Loot is defined **per expedition node** (`ExpeditionNode.loot`) and given when the node is resolved.
* Resources (wood, stone, iron...) are spent in the hub: the **carpentry workshop** builds and upgrades buildings.
  Planned: the **tavern** (temporary expedition buffs, team selection helpers) and the **forge** (permanent upgrades / crafting items to loot or start with).

### 3.4 Saves (decided)
* **Multiple named save files**. The chosen file is the one all saves go to.
* Saves happen **only at safe moments**: hub opening, expedition start, each time the party is back on the map after a node, end of an expedition,
  buildings purchases, manual save from the pause menu (disabled during battles). **Never in the middle of a battle.**
* Quitting during a battle returns to the last map state.

---

## 4. Current status (end of the previous conversation)

Roadmap that was followed:

| Phase | Content | State |
|---|---|---|
| 0 | Decisions (health carry-over, defeat rule, hand-authored graphs, mid-expedition saves) | Done |
| 1 | SceneManager, PlayerProfile, RunState, GameState, HeroCatalog | Done, confirmed by developer |
| 2 | Expedition data (Node/Data/Encounter/Catalog), DAG validation, test expedition generator | Done, confirmed |
| 3 | Expedition scene (map, node states, dialogs, camp, abandon, summary) | Done, confirmed |
| 4 | Battle integration (roster from run, encounter, health carry-over, result back to the map) | Done, confirmed ("everything is working") |
| 5 | Main menu | Done |
| 6 | Save system, then multiple save files with names, load list and delete | Delivered; the developer is using the list and added the delete button |
| 7 | Hub integration: buildings (data + catalog), fixed-position locations hidden until unlocked, carpentry menu, resource bar, loot per node | Done |
| - | **Pause menu** | **Delivered (`pause_menu.gd`) but the explanation message of the integration steps was cut off: see `TECHNICAL_DOCUMENTATION.md` section 12. Untested.** |

---

## 5. Backlog / next steps (suggested order)

1. **Finish the pause menu** integration (autoload scene, `create_timer(..., false)` fix in battle, see technical doc section 12) and have it tested.
2. **Tavern**: menu to choose a temporary expedition buff before launching (data model to design: buff resources, applied at `RunState` start).
   Possibly also move team selection there (the gate menu currently does it).
3. **Forge**: permanent upgrades / craftable items (equipment taken on expeditions). Needs a data model for items and how they modify heroes.
4. **Status system**: `Character.apply_status()` is a stub (only Evasion works). Needs a `StatusComponent` (tick TURNS statuses each turn,
   consume USES statuses, Bleeding damage, Stun skipping a turn), plus status icons UI.
5. **More card effects**: `CardData` has no armor-gain or heal effect yet (support cards only give mana and statuses).
   Extend `StatusApplication` or add a sibling effect resource.
6. **Real enemy actions**: replace the placeholder default attack by attack patterns (melee, ranged, AOE) using the unused `action_pattern` slot idea.
7. **Spawn patterns** AMBUSH / AMBUSHED (`EncounterData.SpawnPattern`) in `Battle._get_spawn_position()`, and map-bounds clamping of movement/knockback using the TileMapLayer.
8. **More objectives** (boss, destroy object, rescue hostage, survive waves; waves need a public spawn function on `Battle`).
9. **Expedition content**: real events (currently stub dialog), destination selection in the gate menu (currently fixed `first_expedition`),
	node icons/art, more expeditions, possibly procedural generation.
10. Hero health upgrades from the forge (`RunState.start()` has a TODO), hero deck editing, rewards choices.
11. Polish: themes/fonts (default font is blurry with pixel art), animations, audio, settings menu, localization, export testing (saves use `user://saves`).

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
* Hub buildings are **placed by hand in the scene** (fixed positions, Heroes of Might and Magic style) and hidden until unlocked.

---

## 7. Godot pitfalls met in this project (avoid repeating)

* Autoload scripts (`GameState`, `SceneManager`, `PauseMenu`) must **not** declare a `class_name` equal to the autoload name.
* Duplicate `class_name` files cause *"Class X hides a global script class"* and make the script invalid (this happened once because of a duplicated file).
* `EditorScript` generators: only **`@tool`** scripts can have methods called in the editor; non-tool resource scripts give placeholder instances
  (properties work, methods do not). That is why `ExpeditionData`, `ExpeditionNode`, `EncounterData` are `@tool` and `BuildingCatalog.validate()` is not called from the tool script.
* A container (`HBoxContainer`) overrides its children's position: cards in the hand are wrapped in a plain `Control` "slot" so they can be raised when selected.
* `event.pressed` on a base `InputEvent` cannot be type-inferred: write `var x: bool = (...)`.
* `Area2D` clicks are blocked by `Control` nodes with Mouse Filter = Stop (set full-screen HUD containers to Ignore) and need *Physics Object Picking*
  enabled on a SubViewport if the game renders inside one (CRT addon).
* `SceneTreeTimer` runs **while the tree is paused** by default: use `create_timer(t, false)` in gameplay code (pause menu).
* JSON stores `StringName` as strings and numbers as floats: `SaveUtils` converts back.
* Typed arrays: build with `append`/`append_array` when unsure (`Array.duplicate()` typing and literal conversions can bite).
* `Dictionary[StringName, int]` exports require Godot 4.4+.
* A function that mixes `await` and plain returns is fine, but a coroutine's early return value is only visible when awaited.
* `Label` minimum width follows its text: use `text_overrun_behavior` to get equal-width columns.
* An hidden `AcceptDialog` OK button + custom buttons is how the project forces **"No" left, "Yes" right** order (ConfirmationDialog order depends on the OS).

---

## 8. How the next agent should start

1. Read this file, then `TECHNICAL_DOCUMENTATION.md`.
2. Ask the developer which of the *Backlog* items to do, and **whether phase 7 and the pause menu were tested** (and the content of any Output warnings).
3. Before modifying a file listed in section 2 as customized, **ask for the current version**.
4. Deliver code, a list of changed files, what to build in the editor (scene trees with unique names), and a short test checklist. Do not run Godot.
