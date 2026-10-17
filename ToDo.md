- Phase 0: Project setup

Set the default texture filter to Nearest and enable 2D pixel snapping in Project Settings.
Create a folder structure, for example scripts/, scenes/, and data/{characters,cards,statuses}/, and add all the .gd files.
Open the project and fix any parse errors. I haven't been able to run the scripts, so expect a few typos.

Phase 1: One character on screen
Build character.tscn with the node tree described earlier. Don't forget the unique names and Local to Scene on the circle shape.
Create two CharacterData .tres files, one ally and one enemy, with sprite tile coordinates from your tileset.
Make a throwaway test scene with one Character.

Done when: the sprite, name, health bar and click all work, and armor/evasion show and hide correctly.

- Phase 2: Content resources

Create StatusData resources for Evasion, Bleeding and Stun. Use the id evasion for Evasion, because apply_status() looks for that id.
Create a handful of CardData resources that cover each rule at least once:
a basic attack
a support card
a mana card
a Quick attack
a backstab (angle 180)
a chained or AOE attack
Fill in the deck array on your ally CharacterData files.

- Phase 3: Battle scene
Build battle.tscn with the tree from the battle.gd header: TileMapLayer, Allies, Enemies, and the two spawn marker containers. Draw a simple map.
Assign character_scene and a roster of 3 allies and 2 or 3 enemies.

Done when: you run the scene and everyone spawns at the markers.

- Phase 4: Test the logic before building real UI
Write a temporary debug script: one button per hand card, plus an End Turn button, 
and print() on the battle signals. Play cards on the first enemy and watch the output.

Done when: you've confirmed damage, armor, evasion, mana, the 3-action limit, 
Quick refunds, kills, the enemy turn, draw-to-6 and victory/defeat all behave. 
Bugs are much cheaper to find here than behind a card UI.

- Phase 5: Card UI
Build card_view.tscn (a Control) that takes a CardInstance and shows name, art,
 description, damage, mana gain or cost, and a Quick tag.
Build a Hand container that rebuilds its card views on deck.hand_changed.
Add card states: hover, selected, and greyed out when can_play_card() is false.

- Phase 6: Targeting flow

This is the most complex part of the UI, so build it in this order:
16. Selecting a card highlights get_valid_targets().
17. Clicking a target (Character.clicked) plays a SINGLE card via await battle.play_card().
18. Add multi-select for MULTIPLE and CHAINED cards with a confirm action, 
    highlight only characters within chain_radius for CHAINED.
19. Add an AOE radius preview.
DONE 20. Add cancel (right click or Esc).
21. Add a destination preview using get_approach_position(), 
    so the player sees where the caster will stand.

- Phase 7: Battle HUD, the first playable milestone
Add the End Turn button, an actions counter, a mana display, a turn or phase label,
and the intent arrows from each enemy to its intent_target, redrawn on intents_changed.
Add a victory/defeat screen on battle_ended.
Block input while phase != PLAYER_TURN.

The intent cutout you plan above the head can listen to intents_changed and read enemy.intent_target. 
A target moving without being replaced doesn’t fire that signal, 
but the cutout shows the sprite, not a position, so it doesn’t need updating.

- Phase 8: Feedback and polish
Add floating damage numbers (damaged), a "Dodge!" popup (dodged), and status icons driven by statuses_changed.
Flip the sprite from facing_angle, add a hit flash, a death effect, and card play and draw animations.

- Phase 9: Fill the known gaps
Status system: add a StatusComponent that ticks TURNS statuses each turn, 
consumes USES statuses, and applies Bleeding damage and Stun. Decide whether Evasion moves into it.
Card effects: add armor gain and heal as card effects (the support card gap).
Real enemy actions: replace the placeholder attack with enemy attack patterns 
(melee, ranged, AOE) and use the action_pattern slot in CharacterData.
Map bounds: clamp movement and knockback to the map shape using the TileMapLayer, 
and handle obstacles if you add any.
Objectives: turn _is_victory() into a small objective system for hostage and chest missions.
Phase 10: Roguelite layer
Mission setup with spawn patterns (ambush, ambushed) replacing _get_spawn_position().
Team selection (3 allies) and passing the roster into start_battle().
Run structure: map or node progression, rewards, deck building, saving.
Suggested milestones
After phase 4: the rules are proven, even without UI.
After phase 7: you can play a full fight with a mouse.
After phase 9: it's ready for content.

Phase 6 is the one most likely to need design decisions, 
such as how the player confirms multi-target cards. 
I can write the targeting controller or the card view script next if you want. 
I can also put this list in a markdown file as a checklist if that would help.


## Expedition todo

Phase 0: Decisions (each one can wait until its phase)
Health carry-over (needed in phase 4): do heroes keep their health between battles of an expedition, as in Slay the Spire, or reset? The camp node only means something if health carries over, so I’d carry it over.
Defeat (phase 3): what happens on defeat? Options are losing the loot, keeping part of it, or keeping everything.
Graph (phase 2): hand-authored graphs first, with a procedural generator later. I’d start hand-authored.
Mid-expedition saves (phase 6): can the player quit mid-expedition and resume? I’d start with save at the hub and at the end of each expedition only.
Phase 1: Foundations (game flow and state)
Scene flow: a SceneManager autoload with named routes (main menu, hub, expedition, battle) and a simple fade.
PlayerProfile: the persistent data, kept as plain data so it can be saved later. It holds the unlocked hero ids, the resources (wood, stone, iron...), and the hub state (unlocked places and upgrade levels).
RunState: the temporary state of one expedition. It holds the team, the expedition, the current node, the visited nodes, the loot gathered so far and the heroes’ health.
GameState autoload that holds the profile and the current run.
Hero catalog: one place that maps hero id to CharacterData. The gate menu uses it instead of a hand-filled list, and the save system will need it too.

Done when: the gate reads unlocked heroes from the profile and launch() stores the team in the run state.

Phase 2: Expedition data
ExpeditionNode resource: an id, a type (battle, camp, event, boss, end), the encounter if it’s a battle, the ids of the nodes it leads to, and a position hint for the layout.
ExpeditionData resource: a destination name, its goal, and its list of nodes. It can have several end nodes for secret objectives.
EncounterData resource: the enemies, the objective and the spawn pattern of one battle. battle.gd will read this later.
DAG validation: no cycles, every node reachable from the start, and every path leading to an end.
A first test expedition as a .tres: start, two branches, merge, boss.
Phase 3: Expedition scene
Layout: put each node in a column by its depth in the graph, and position it from that.
Display: draw the nodes and the links between them. The whole path stays visible, with visited, current and reachable nodes shown differently.
Choosing: clicking a reachable node moves the run forward.
Node dispatch: a battle node goes to the battle, a camp opens a rest screen, an event is a stub, and an end node finishes the expedition. Start with a stub battle that just returns “victory”.
Gate to expedition: launch() starts the run and changes to the expedition scene.
Expedition end: a summary screen, loot added to the profile, then back to the hub.

Done when: you can walk a whole expedition from the gate and return to the hub, with the battles stubbed.

Phase 4: Battle integration
Roster source: battle.gd reads the team from the run state and the enemies from the encounter. Keep the inspector roster as a fallback so you can still test a battle on its own.
Objective: it comes from the encounter.
Health carry-over: HealthComponent.initialize() needs a current-health parameter.
Battle end: victory returns to the expedition and records the result. Defeat ends the run. This is where the Continue button of the victory panel connects.
Phase 5: Main menu
Main menu scene: New game, Continue (disabled when there’s no save) and Quit.
New game: create a default profile (starting heroes), then go to the hub. Set the main menu as the project’s start scene.
Phase 6: Save system
Format: a versioned JSON file in user://, referencing heroes and places by id and never by resource path. A version field lets you migrate old saves later.
SaveManager: save and load, written safely (to a temporary file, then renamed), with handling for a corrupted file.
Autosave: on entering the hub and at the end of an expedition.
Wiring: the main menu’s Continue loads the save, and the hub and gate read everything from the profile.
Later: resuming mid-expedition, which means saving the run state.
Phase 7: Hub integration
Hub state: unlocked places and upgrade levels come from the profile, and a resource display shows the stock.
Rewards: expedition loot flows into the profile, which the forge and tavern menus will spend later.
