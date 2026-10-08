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
20. Add cancel (right click or Esc).
21. Add a destination preview using get_approach_position(), 
    so the player sees where the caster will stand.

- Phase 7: Battle HUD, the first playable milestone
Add the End Turn button, an actions counter, a mana display, a turn or phase label,
and the intent arrows from each enemy to its intent_target, redrawn on intents_changed.
Add a victory/defeat screen on battle_ended.
Block input while phase != PLAYER_TURN.

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
