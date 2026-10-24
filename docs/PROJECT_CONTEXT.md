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
  Review code statically and carefully instead.
* The developer **edits their own copies** of the files, so **never assume your version is the current one**. Files arrive in `/mnt/user-data/uploads`
  (sometimes with a suffix such as `character_1.gd`, `character_6377fa.gd`: the newest upload is the current one). **Check that an uploaded file really contains what its name says**
  (an `Expedition.tscn` once turned out to contain the Character scene: it had been overwritten by a "Save Scene As" mistake, and a rebuilt scene was delivered).
  Known customizations on the developer's side:
  * `battle.gd`: `character_scene` is `@onready` instead of `@export`; `roster` export pre-filled for debugging (3 heroes + 4 goblins). Status-system changes were delivered as a full file based on their copy (`take_hit`, status ticks, stun, `create_timer(..., false)`).
  * `character.gd` (**heavily customized**, latest upload `character_6377fa.gd`): `%UI/%HealthBar`, `%UI/%ArmorBar`, `%UI/%HealthValue`, `%UI/%ArmorValue`, `%UI/%IntentIcon` (intent icon now lives inside the UI sub-scene),
    optional `%UI/%StatusIcons`. The UI is built for **1920x1080** and the `UI` node is **scaled down (about 0.27)**, so the constants are large (`STATUS_ICON_SIZE = 80`, `STATUS_FONT_SIZE = 40`, `UI_HEIGHT_ABOVE_HEAD = 20`).
    The health value label shows **only the current health** (no maximum, the bar tells the rest). Click circle: they replaced the delivered formula by `shape.radius = size.x * CLICK_RADIUS_FACTOR + 5`.
  * `CardInstance.gd` and `card_view.gd` were customized (card type shown as text with a debug color per type, attack/critical damage display). **Always ask for the current versions before editing these.**
  * `main_menu.gd`: "Delete file" button per save row with confirmation popup.
  * `HeroSlot.gd`: fixed for `starting_statuses` (they removed `CharacterData.starting_evasion`); a status list is now shown in the stats text.
  * `CharacterData.gd`: `starting_evasion` was **removed** and replaced by `starting_statuses: Dictionary[StatusData, int]`.
  * Prefer giving **snippets + a list of what changed** when a file might have been modified by the developer; **ask them to upload the current file** before large changes.
    When the current version is available, edit **that** version and deliver the full file (this worked well for `battle.gd`, `character.gd`, `GameState.gd`, `menu_gate.gd`).
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

**Opened loose ends:** `HealthComponent` still contains its old evasion code (`evasion`, `add_evasion`, `evasion_changed`, `dodged`), now unused: the file has not been seen by the agent, ask for it to remove it (and keep any "Dodged" feedback working by emitting from `Character.take_hit`).

---

## 5. Backlog / next steps (suggested order)

1. **Verify the unconfirmed items** of phase 8 and the Expedition scene (see technical doc section 16), and send `health_component.gd` to remove the dead evasion code.
2. **Status follow-ups**: hover tooltip (name + description) on status icons (needs a hover test that does not block clicks), `USES` hooks (e.g. a vulnerability consumed on hit, call `StatusComponent.consume()` from the damage code),
   `DISPEL` (remove buffs, mirror of Cleanse), partial cleanse ("remove 1 debuff"), more statuses (Poison, Weakness, Strength...), card descriptions generated from effects.
3. **Real enemy actions**: attack patterns (melee, ranged, AOE) instead of the placeholder default attack, including enemies that apply Bleeding/Stun to heroes (this will make the "status applied during its own side's phase decays immediately" limitation matter).
4. **Tavern**: menu to choose a temporary expedition buff before launching (data model to design: buff resources, applied at `RunState` start; can reuse `StatusData` through `starting_statuses`-like data).
   Possibly also move team selection there (the gate menu currently does it).
5. **Forge**: permanent upgrades / craftable items (equipment taken on expeditions). Needs a data model for items and how they modify heroes.
6. **Spawn patterns** AMBUSH / AMBUSHED (`EncounterData.SpawnPattern`) in `Battle._get_spawn_position()`, and map-bounds clamping of movement/knockback using the TileMapLayer.
7. **More objectives** (boss, destroy object, rescue hostage, survive waves; waves need a public spawn function on `Battle`).
8. **Expedition content**: real events (currently stub dialog), destination selection in the gate menu (currently fixed `first_expedition`), node icons/art, more expeditions, possibly procedural generation.
9. Hero health upgrades from the forge (`RunState.start()` has a TODO), hero deck editing, rewards choices.
10. **Visual health system** (chunks every 10 points on the health/armor bars, the developer mentioned it for later).
11. Polish: themes/fonts (default font is blurry with pixel art), animations, audio, settings menu, localization, export testing (saves use `user://saves`), a consistent UI scaling strategy for 1920x1080.

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
* A scene saved under the wrong name destroys the original (`Expedition.tscn` was overwritten by the Character scene): check the editor tab before Ctrl+S and use version control.
* `%UI` can be a Control or a Node2D: keep it untyped (`@onready var ui = %UI`) when only `position`/`scale`/transform are needed.
* Generated `Control`s inside a character (status icons, labels) must use `mouse_filter = IGNORE` or they block clicks on the `Area2D`.
* Container sizes are only final a couple of frames after spawning: do layout-dependent placement after `await get_tree().process_frame` (twice) and re-run it on `item_rect_changed`.
* `Label` outline/size set by code must account for a **scaled UI node** (the developer's UI is scaled to ~0.27, hence the big font/icon constants).
* A formatted string with `%d` and a Dictionary argument fails silently (the `%d` stays in the text): format dictionaries yourself.
* Enums that are saved in `.tres` as integers: **append** new values at the end (`Effect.CLEANSE` was added last) so existing resources keep their meaning.
* An hidden `AcceptDialog` OK button + custom buttons is how the project forces **"No" left, "Yes" right** order (ConfirmationDialog order depends on the OS).

---

## 8. How the next agent should start

1. Read this file, then `TECHNICAL_DOCUMENTATION.md`. If only the paths of the uploaded files are listed, read them from `/mnt/user-data/uploads` (the technical doc is large).
2. Ask the developer which of the *Backlog* items to do, and **which of the [U] items were tested** (and the content of any Output warnings).
3. Before modifying a file listed in section 2 as customized, **ask for the current version** (and verify the upload really is that file).
4. Deliver code, a list of changed files, what to build in the editor (scene trees with unique names), and a short test checklist. Do not run Godot.
