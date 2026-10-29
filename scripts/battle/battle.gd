class_name Battle
extends Node2D
## Runs one fight: spawning, turn flow, card resolution and win/lose.
##
## Expected scene tree (nodes marked with unique names, "Access as Unique Name"):
##   Battle (Node2D)           <- this script
##   ├── Map (TileMapLayer)    <- decor/layout, not used by the logic yet
##   ├── %Allies (Node2D)      <- ally Characters are added here
##   ├── %Enemies (Node2D)     <- enemy Characters are added here
##   ├── %AllySpawns (Node2D)  <- Marker2D children = placeholder ally positions
##   └── %EnemySpawns (Node2D) <- Marker2D children = placeholder enemy positions
##
## UI talks to this node through signals and these methods:
##   get_valid_targets(), is_valid_selection(), can_play_card(), play_card(), end_player_turn()

enum Phase { SETUP, PLAYER_TURN, RESOLVING, ENEMY_TURN, ENDED }

signal phase_changed(phase: Phase)
signal turn_started(turn: int)
signal actions_changed(actions_left: int)
signal mana_changed(mana: int)
signal character_clicked(character: Character)  # forwarded from every Character
signal intents_changed  # an enemy picked a new target (redraw the intent arrows)
signal card_played(card: CardInstance)
signal objective_updated  # the objective may have changed (refresh the HUD)
signal battle_ended(victory: bool)

const ACTIONS_PER_TURN := 3
const CRIT_MULTIPLIER := 1.5
const KNOCKBACK_DISTANCE := {
	CardData.Knockback.STANDARD: 48.0,
	CardData.Knockback.FORCEFUL: 96.0,
}
const MOVE_TIME := 0.25
const KNOCKBACK_TIME := 0.15
const ENEMY_ACTION_DELAY := 0.4

# Finding a free spot around a target (see _find_free_position)
const PLACEMENT_ANGLE_STEP := PI / 12.0  # 15 degrees between two tested spots
const PLACEMENT_STEPS := 24              # 24 x 15 degrees = a full turn
const PLACEMENT_RINGS := 4               # how many times the distance grows by one body radius
const PLACEMENT_TOLERANCE := 0.5         # px: bodies that merely touch don't overlap

@onready var character_scene: PackedScene = preload("res://scenes/character/character.tscn")
## Everyone to spawn. Each CharacterData's `team` decides which side it joins.
## If filled in, the battle starts automatically (handy for testing).
@export var roster: Array[CharacterData] = [
	   preload("res://data/character/allies/knight.tres"),
	   preload("res://data/character/allies/thief.tres"),
	   preload("res://data/character/allies/wizard.tres"),
	   preload("res://data/character/enemies/goblin.tres"),
	   preload("res://data/character/enemies/goblin.tres"),
	   preload("res://data/character/enemies/goblin.tres"),
	   preload("res://data/character/enemies/goblin.tres"),
]

## What has to be done to win. If empty, a KillAllObjective is created.
## Add an objective node to the scene and assign it here to change the mission goal.
@export var objective: BattleObjective

@onready var allies_root: Node2D = %Allies
@onready var enemies_root: Node2D = %Enemies
@onready var ally_spawns: Node2D = %AllySpawns
@onready var enemy_spawns: Node2D = %EnemySpawns

## Living characters only. Dead ones are removed as soon as they die.
var allies: Array[Character] = []
var enemies: Array[Character] = []
var deck := CardDeck.new()

## Set when the battle comes from an expedition node.
var encounter: EncounterData
## Only STANDARD exists for now (see EncounterData.SpawnPattern); _get_spawn_position will use it.
var spawn_pattern: EncounterData.SpawnPattern = EncounterData.SpawnPattern.STANDARD

var phase: Phase = Phase.SETUP
var turn := 0
var actions_left := 0
var mana := 0  # shared by the whole team

var _in_expedition := false  # true when the heroes and enemies come from a run
var _dead: Array[Character] = []  # hidden, freed once the current action ends
var _warned_no_actions := {}  # enemy ids without actions already reported (one warning each)
var _fallback_action: EnemyAction  # basic melee used by enemies that have no action


func _ready() -> void:
	_create_intent_overlay()
	# Inside an expedition the fight comes from the current node. Otherwise
	# (battle scene tested alone) the `roster` set in the inspector is used.
	if _start_from_run():
		return
	if not roster.is_empty():
		start_battle(roster)


## Draws the AOE circles planned by enemies. Built by code, placed right before %Allies
## so the circles are under the characters.
func _create_intent_overlay() -> void:
	var overlay := IntentOverlay.new()
	overlay.battle = self
	var parent := allies_root.get_parent()
	parent.add_child(overlay)
	parent.move_child(overlay, allies_root.get_index())


## Starts the battle of the current expedition node: the heroes who can fight
## (with the health they have left) against the enemies of the encounter.
## Returns false when there is no run or the node has no encounter.
func _start_from_run() -> bool:
	if not GameState.has_run():
		return false
	var expedition := GameState.get_run_expedition()
	if expedition == null:
		return false
	var node := expedition.get_node_by_id(GameState.run.current_node_id)
	if node == null or node.encounter == null:
		return false

	_in_expedition = true
	encounter = node.encounter
	spawn_pattern = encounter.spawn_pattern
	if encounter.objective_scene != null:  # otherwise the default: defeat all enemies
		objective = encounter.objective_scene.instantiate() as BattleObjective
		add_child(objective)

	var characters: Array[CharacterData] = []
	characters.append_array(GameState.get_run_fighters())
	# Hand-made enemies and/or enemies generated from the expedition's pool and the node's budget.
	# The battle can place as many enemies as there are %EnemySpawns markers.
	characters.append_array(EncounterGenerator.build_enemies(
		expedition, node, GameState.run.rng_seed, enemy_spawns.get_child_count()))
	start_battle(characters)
	return true


## "Continue" after the battle: back to the expedition map, or a restart when the
## battle scene is tested alone.
func leave_battle() -> void:
	if phase != Phase.ENDED:
		return
	if _in_expedition:
		SceneManager.go_to(&"expedition")
	else:
		get_tree().reload_current_scene()


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

func start_battle(characters: Array[CharacterData]) -> void:
	_spawn_roster(characters)
	_update_facings()
	deck.build_from(allies)
	for enemy in enemies:
		_plan_intent(enemy)
	mana = 0
	turn = 0
	_start_objective()
	_start_player_turn()


func _start_objective() -> void:
	if objective == null:
		objective = KillAllObjective.new()
		add_child(objective)
	objective.start(self)
	objective_updated.emit()


## Heroes of an expedition start with the health they have left (-1 = full health).
func _starting_health(data: CharacterData) -> int:
	if _in_expedition and data.team == CharacterData.Team.ALLY:
		return GameState.run.get_health(data.id)
	return -1


func _spawn_roster(characters: Array[CharacterData]) -> void:
	for data in characters:
		var is_ally := data.team == CharacterData.Team.ALLY
		var team := allies if is_ally else enemies

		var character: Character = character_scene.instantiate()
		character.setup(data, _starting_health(data))
		(allies_root if is_ally else enemies_root).add_child(character)
		character.global_position = _get_spawn_position(is_ally, team.size())
		character.died.connect(_on_character_died)
		character.clicked.connect(character_clicked.emit)
		team.append(character)


## Placeholder: fixed markers. Replace this one function later for
## ambush / ambushed patterns.
func _get_spawn_position(is_ally: bool, index: int) -> Vector2:
	var points := ally_spawns if is_ally else enemy_spawns
	return points.get_child(index % points.get_child_count()).global_position


# ---------------------------------------------------------------------------
# Player turn
# ---------------------------------------------------------------------------

func _start_player_turn() -> void:
	turn += 1
	_start_of_turn_statuses(allies)  # Bleeding may kill a hero
	if _check_battle_end():
		return
	_set_phase(Phase.PLAYER_TURN)
	_set_actions(ACTIONS_PER_TURN)
	deck.draw_to_full()
	turn_started.emit(turn)


## Call this from the "End turn" button.
func end_player_turn() -> void:
	if phase != Phase.PLAYER_TURN:
		return
	_end_of_turn_statuses(allies)
	await _run_enemy_turn()


func can_play_card(card: CardInstance) -> bool:
	return (
		phase == Phase.PLAYER_TURN
		and actions_left > 0
		and deck.hand.has(card)
		and allies.has(card.caster)
		and not card.caster.is_incapacitated()
		and (card.data.card_type != CardData.Type.MANA or mana >= card.mana_cost)
		and _has_required_charges(card)
	)


## Charges (stacks of CardData.consume_status) this card would spend right now: what the caster
## holds, at most `consume_amount` (0 = no limit). 0 if the card consumes nothing.
## The UI can use it to preview the bonus.
func get_charges_to_spend(card: CardInstance) -> int:
	var data := card.data
	if data.consume_status == null:
		return 0
	var held := card.caster.status_component.get_stacks(data.consume_status)
	return held if data.consume_amount <= 0 else mini(held, data.consume_amount)


## Extra damage per hit the card would get from its charges right now (UI preview).
func get_charge_bonus_damage(card: CardInstance) -> int:
	return card.data.bonus_damage_per_stack * get_charges_to_spend(card)


## False when the card needs charges (consume_required) and the caster has too few.
func _has_required_charges(card: CardInstance) -> bool:
	var data := card.data
	if data.consume_status == null or not data.consume_required:
		return true
	return get_charges_to_spend(card) >= maxi(data.consume_amount, 1)


## Everyone the card could be aimed at.
func get_valid_targets(card: CardInstance) -> Array[Character]:
	match card.data.target_team:
		CardData.TargetTeam.ENEMY:
			return enemies.duplicate()
		CardData.TargetTeam.ALLY:
			return allies.duplicate()
	return [card.caster]


## How many targets the player picks for this card (1 for SINGLE and AOE).
func get_max_picks(card: CardInstance) -> int:
	match card.data.target_type:
		CardData.TargetType.MULTIPLE, CardData.TargetType.CHAINED:
			return card.data.max_targets
	return 1


## CHAINED cards can pick the same character several times (the chain bounces).
func allows_repeat_picks(card: CardInstance) -> bool:
	return card.data.target_type == CardData.TargetType.CHAINED


## Who can be added to the picks made so far.
## Already picked characters are excluded, except for CHAINED cards (see allows_repeat_picks).
## MULTIPLE: anyone within select_radius of the caster (0 = no limit).
## CHAINED: the first pick is free, then each pick must be within chain_radius
## of the previous one (the previous target itself counts, distance 0).
func get_pickable_targets(card: CardInstance, selected: Array[Character]) -> Array[Character]:
	var result: Array[Character] = []
	if selected.size() >= get_max_picks(card):
		return result

	var data := card.data
	for candidate in get_valid_targets(card):
		if selected.has(candidate) and not allows_repeat_picks(card):
			continue
		match data.target_type:
			CardData.TargetType.MULTIPLE:
				var reach := candidate.global_position.distance_to(card.caster.global_position)
				if data.select_radius > 0.0 and reach > data.select_radius:
					continue
			CardData.TargetType.CHAINED:
				if not selected.is_empty():
					var jump := candidate.global_position.distance_to(selected.back().global_position)
					if jump > data.chain_radius:
						continue
		result.append(candidate)
	return result


## Checks the player's picks, in order, with the same rules as get_pickable_targets().
## SINGLE / AOE: exactly 1 pick (AOE then hits everything around it).
## MULTIPLE / CHAINED: 1 to max_targets picks.
func is_valid_selection(card: CardInstance, selected: Array[Character]) -> bool:
	if selected.is_empty():
		return false

	var picked: Array[Character] = []
	for target in selected:
		if not get_pickable_targets(card, picked).has(target):
			return false
		picked.append(target)
	return true


## Plays a card. Use `await battle.play_card(card, targets)` so the UI waits
## for the animations. Does nothing if the play is not allowed.
func play_card(card: CardInstance, selected: Array[Character]) -> void:
	if not can_play_card(card) or not is_valid_selection(card, selected):
		return

	_set_phase(Phase.RESOLVING)
	var data := card.data
	var caster := card.caster
	var targets := get_affected_targets(card, selected)

	# 1. Pay: one action, plus mana for MANA cards
	_set_actions(actions_left - 1)
	if data.card_type == CardData.Type.MANA:
		_set_mana(mana - card.mana_cost)

	# 1b. Spend the charges once for the whole card (a chain or an AOE gives the same bonus to each
	# hit). Done before the statuses of step 5, so a card can spend charges and give new ones.
	var spent := get_charges_to_spend(card)
	if spent > 0:
		caster.status_component.consume(data.consume_status, spent)
	var bonus_damage := data.bonus_damage_per_stack * spent

	# 2. Move, hit and knock back
	var killed: Array[Character] = []
	var attacks := data.target_team == CardData.TargetTeam.ENEMY
	if data.target_type == CardData.TargetType.CHAINED:
		# The caster follows the chain: walk to each target, hit it, move on
		for target in targets:
			if target.is_dead():
				continue  # killed earlier in this same chain
			if attacks:
				await _approach(card, target)
			var hit: Array[Character] = [target]
			_deal_damage(card, hit, killed, bonus_damage)
			await _knock_back(card, hit)
	else:
		# Attack cards walk to the first pick, then every target is hit at once
		if attacks:
			await _approach(card, selected[0])
		_deal_damage(card, targets, killed, bonus_damage)
		await _knock_back(card, targets)

	# 5. Statuses, then mana, Quick refund and cleanup
	_apply_effects(card, targets, killed)
	if data.card_type != CardData.Type.MANA:
		_set_mana(mana + card.mana_generation)
	if data.quick and not killed.is_empty():
		_set_actions(actions_left + 1)

	deck.discard(card)
	card_played.emit(card)
	_free_dead()
	_update_facings()

	if not _check_battle_end():
		_set_phase(Phase.PLAYER_TURN)


## Who the card will really hit for these picks. Only AOE differs from the picks:
## it hits everyone of the target's team within aoe_radius of the picked target.
## (The UI uses this to preview the area.)
func get_affected_targets(card: CardInstance, selected: Array[Character]) -> Array[Character]:
	if card.data.target_type != CardData.TargetType.AOE:
		return selected
	var center := selected[0].global_position
	var result: Array[Character] = []
	for candidate in get_valid_targets(card):
		if candidate.global_position.distance_to(center) <= card.data.aoe_radius:
			result.append(candidate)
	return result


## Where the caster really stands to hit `target` when coming from `from`:
## the card's ideal spot (CardData.get_approach_position), moved to the nearest
## free place if another character is in the way. Used by the move and by the preview.
func find_approach_position(card: CardInstance, from: Vector2, target: Character) -> Vector2:
	var ideal := card.data.get_approach_position(from, target.global_position)
	return _free_position(ideal, from, target, card.caster)


## `ideal` is where `mover` would like to stand next to `target`. Returns `from`
## when no move is needed, otherwise the closest free spot to `ideal`.
func _free_position(ideal: Vector2, from: Vector2, target: Character, mover: Character) -> Vector2:
	return _free_position_at(ideal, from, target.global_position, mover)


## Same as _free_position, around a point instead of a character (the spot of an AOE).
func _free_position_at(ideal: Vector2, from: Vector2, center: Vector2, mover: Character) -> Vector2:
	if ideal.is_equal_approx(from):
		return from  # already in range, the mover doesn't walk
	return _find_free_position(ideal, center, mover)


## Searches around `center` for a spot where `mover` doesn't overlap anyone:
## 1. try the ideal spot, then turn around the center, alternating sides
##    (+15, -15, +30, -30 degrees...) so the first free spot is the closest to the ideal one;
## 2. if the whole circle is blocked, grow the distance by the mover's radius and turn again.
## Falls back to the ideal spot if nothing is free.
func _find_free_position(ideal: Vector2, center: Vector2, mover: Character) -> Vector2:
	var offset := ideal - center
	var base_radius := offset.length()
	var base_angle := offset.angle()

	for ring in PLACEMENT_RINGS:
		var radius := base_radius + ring * mover.shape.radius
		for step in PLACEMENT_STEPS:
			var turns := ceili(step / 2.0)                    # 0, 1, 1, 2, 2, 3...
			var side := 1.0 if step % 2 == 1 else -1.0        # + first, then -
			var angle := base_angle + side * turns * PLACEMENT_ANGLE_STEP
			var spot := center + Vector2.from_angle(angle) * radius
			if _is_spot_free(spot, mover):
				return spot
	return ideal


## True if a body of the mover's size standing at `spot` overlaps no other character.
func _is_spot_free(spot: Vector2, mover: Character) -> bool:
	for team in [allies, enemies]:
		for other in team:
			if other == mover:
				continue
			var min_gap: float = mover.shape.radius + other.shape.radius - PLACEMENT_TOLERANCE
			if spot.distance_to(other.global_position) < min_gap:
				return false
	return true


## Where the caster will stand after each step of its move, for the UI preview.
## Empty for cards that make no one walk (support cards) or when nothing is picked yet.
func get_approach_positions(card: CardInstance, selected: Array[Character]) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if card.data.target_team != CardData.TargetTeam.ENEMY or selected.is_empty():
		return result

	# A chain walks to every pick, other cards only to the first one
	var walk_to: Array[Character] = [selected[0]]
	if card.data.target_type == CardData.TargetType.CHAINED:
		walk_to = selected

	var stand_at := card.caster.global_position
	for target in walk_to:
		stand_at = find_approach_position(card, stand_at, target)
		if result.is_empty() or not result.back().is_equal_approx(stand_at):
			result.append(stand_at)
	return result


## The caster walks to the position this card needs around the target, looking at it.
func _approach(card: CardInstance, target: Character) -> void:
	var caster := card.caster
	var destination := find_approach_position(card, caster.global_position, target)
	caster.face_towards(target.global_position)  # look at the target while walking
	await _move_characters({caster: destination}, MOVE_TIME)
	caster.face_towards(target.global_position)  # a backstab ends up on the other side


## One hit on each target (dodged by Evasion in the StatusComponent, then armor and health).
## Characters that die are added to `killed`. `bonus` is the extra damage from spent charges.
func _deal_damage(card: CardInstance, targets: Array[Character], killed: Array[Character], bonus: int = 0) -> void:
	if card.damage + bonus <= 0:
		return
	var amount := roundi((card.damage + bonus) * (CRIT_MULTIPLIER if card.critical else 1.0))
	for target in targets:
		var was_alive := not target.is_dead()
		target.take_hit(amount)
		if was_alive and target.is_dead():
			killed.append(target)


## Pushes survivors away from the caster, all at the same time.
func _knock_back(card: CardInstance, targets: Array[Character]) -> void:
	if card.data.knockback == CardData.Knockback.NONE:
		return
	var pushes := {}
	for target in targets:
		if not target.is_dead():
			var direction := card.caster.global_position.direction_to(target.global_position)
			pushes[target] = target.global_position + direction * KNOCKBACK_DISTANCE[card.data.knockback]
	await _move_characters(pushes, KNOCKBACK_TIME)


func _apply_effects(card: CardInstance, targets: Array[Character], killed: Array[Character]) -> void:
	for effect in card.get_effects(StatusApplication.Trigger.ON_PLAY):
		if effect.recipient == StatusApplication.Recipient.SELF:
			card.caster.apply_status(effect.status, effect.stacks)  # once per card
		else:
			for target in targets:
				if not target.is_dead():
					target.apply_status(effect.status, effect.stacks)

	# ON_KILL: once per kill. Only SELF makes sense (the target is already dead).
	for effect in card.get_effects(StatusApplication.Trigger.ON_KILL):
		if effect.recipient == StatusApplication.Recipient.SELF:
			for _kill in killed:
				card.caster.apply_status(effect.status, effect.stacks)


# ---------------------------------------------------------------------------
# Enemy turn
# ---------------------------------------------------------------------------

func _run_enemy_turn() -> void:
	_set_phase(Phase.ENEMY_TURN)
	_start_of_turn_statuses(enemies)  # Bleeding may kill enemies
	if _check_battle_end():
		return
	for enemy in enemies.duplicate():
		if not enemies.has(enemy):
			continue
		await _enemy_act(enemy)
		if _check_battle_end():
			return
		await get_tree().create_timer(ENEMY_ACTION_DELAY, false).timeout  # false: frozen by the pause menu
	_end_of_turn_statuses(enemies)
	_start_player_turn()


## One enemy's turn: skip if stunned, charge if the action has a windup, otherwise carry out
## the planned action, then plan the next one (shown to the player during their turn).
func _enemy_act(enemy: Character) -> void:
	if enemy.is_incapacitated():  # stunned or asleep
		return  # turn skipped (a windup does not progress either), the stun loses a stack at the end of the enemy phase
	if not _intent_is_valid(enemy):
		_plan_intent(enemy)
	var intent := enemy.intent
	if intent == null:
		return

	if intent.windup_left > 0:  # charging: no action this turn
		intent.windup_left -= 1
		enemy.refresh_intent()
		return

	await _execute_intent(enemy, intent)
	if enemies.has(enemy):
		_plan_intent(enemy)  # telegraph the next action


## Walks to the target (or to the AOE spot), hits, then applies the effects.
## Every kind of EnemyAction uses this: only the targets and the numbers change.
func _execute_intent(enemy: Character, intent: EnemyIntent) -> void:
	var action := intent.action
	var is_area := action.kind == EnemyAction.Kind.AOE
	var focus := intent.spot if is_area else intent.target.global_position

	var ideal := CardData.closest_in_range(enemy.global_position, focus, action.approach_distance)
	var destination := _free_position_at(ideal, enemy.global_position, focus, enemy)
	enemy.face_towards(focus)
	await _move_characters({enemy: destination}, MOVE_TIME)
	enemy.face_towards(focus)

	var targets := _intent_targets(intent)  # a copy: deaths below change `allies`
	var damage := action.get_damage()
	if damage > 0:
		for target in targets:
			target.take_hit(damage)
	_apply_action_effects(enemy, action, targets)
	_free_dead()
	_update_facings()


## Who the intent hits: everyone of the heroes inside the circle for an AOE
## (checked now, so a hero who walked away is spared), otherwise the single target.
func _intent_targets(intent: EnemyIntent) -> Array[Character]:
	var result: Array[Character] = []
	if intent.action.kind == EnemyAction.Kind.AOE:
		for ally in allies:
			if ally.global_position.distance_to(intent.spot) <= intent.action.aoe_radius:
				result.append(ally)
	elif intent.target != null and not intent.target.is_dead():
		result.append(intent.target)
	return result


## Statuses of an enemy action. TARGET = the ones hit (or the buffed enemy), SELF = the caster.
## The trigger is ignored: everything happens when the action resolves (ON_KILL is skipped).
func _apply_action_effects(enemy: Character, action: EnemyAction, targets: Array[Character]) -> void:
	for effect in action.effects:
		if effect.trigger != StatusApplication.Trigger.ON_PLAY:
			continue
		if effect.recipient == StatusApplication.Recipient.SELF:
			enemy.apply_status(effect.status, effect.stacks)
		else:
			for target in targets:
				if not target.is_dead():
					target.apply_status(effect.status, effect.stacks)


# ---------------------------------------------------------------------------
# Enemy intents (what each enemy plans to do next turn)
# ---------------------------------------------------------------------------

## Chooses the next action of an enemy and who/where it aims at. The player sees it
## (head of the target, action name, AOE circle) and can react during their turn.
func _plan_intent(enemy: Character) -> void:
	if not is_instance_valid(enemy):
		return
	var action := _pick_action(enemy)
	if action == null:  # nothing possible (for example no hero left)
		enemy.intent = null
		intents_changed.emit()
		return

	var intent := EnemyIntent.new(action)
	if action.kind == EnemyAction.Kind.AOE:
		intent.spot = allies.pick_random().global_position  # fixed now: heroes can leave the circle
	else:
		intent.target = _candidates_for(action, enemy).pick_random()
	enemy.intent = intent
	_face_intent(enemy)
	intents_changed.emit()


## Weighted random choice among the actions that have at least one possible target.
func _pick_action(enemy: Character) -> EnemyAction:
	var actions := _get_actions(enemy)
	var options: Array[EnemyAction] = []
	var total := 0
	for action: EnemyAction in actions:
		if action == null or _candidates_for(action, enemy).is_empty():
			continue
		options.append(action)
		var weight: int = actions[action]
		total += maxi(weight, 0)
	if options.is_empty():
		return null
	if total <= 0:
		return options.pick_random()  # every weight is 0: all equally likely

	var roll := randi_range(1, total)
	for action in options:
		var weight: int = actions[action]
		roll -= maxi(weight, 0)
		if roll <= 0:
			return action
	return options.back()


## The actions of an enemy, or a basic melee attack (with a warning) when none is set.
func _get_actions(enemy: Character) -> Dictionary:
	if not enemy.data.actions.is_empty():
		return enemy.data.actions
	if not _warned_no_actions.has(enemy.data.id):
		_warned_no_actions[enemy.data.id] = true
		push_warning("%s has no EnemyAction in CharacterData.actions: using a basic melee attack." % enemy.data.id)
	if _fallback_action == null:
		_fallback_action = EnemyAction.new()
		_fallback_action.display_name = "Attack"
	return {_fallback_action: 1}


## Everyone this action can be aimed at: the heroes, or for a BUFF the other enemies.
func _candidates_for(action: EnemyAction, enemy: Character) -> Array[Character]:
	var pool: Array[Character] = []
	if action.targets_own_side():
		for other in enemies:
			if other != enemy or action.can_target_self:
				pool.append(other)
	else:
		pool.append_array(allies)
	return pool


## False when the planned target is gone (or nothing is planned).
func _intent_is_valid(enemy: Character) -> bool:
	var intent := enemy.intent
	if intent == null:
		return false
	if intent.action.kind == EnemyAction.Kind.AOE:
		return true
	var target := enemy.intent_target
	return target != null and (allies.has(target) or enemies.has(target))


## The target of an intent died: keep the same action (and its windup) on a new target,
## or plan something else if the action has no possible target anymore.
func _retarget_intent(enemy: Character) -> void:
	var intent := enemy.intent
	var pool := _candidates_for(intent.action, enemy)
	if pool.is_empty():
		_plan_intent(enemy)
		return
	intent.target = pool.pick_random()
	enemy.refresh_intent()
	_face_intent(enemy)


## The enemy looks at what it plans to hit (or at the AOE spot).
func _face_intent(enemy: Character) -> void:
	var intent := enemy.intent
	if intent == null:
		return
	if intent.action.kind == EnemyAction.Kind.AOE:
		enemy.face_towards(intent.spot)
	elif enemy.intent_target != null:
		enemy.face_towards(enemy.intent_target.global_position)


# ---------------------------------------------------------------------------
# Statuses (Bleeding, Stun...)
# ---------------------------------------------------------------------------

## Start of a side's turn: damage over time. Deaths are handled as usual.
func _start_of_turn_statuses(team: Array[Character]) -> void:
	for character in team.duplicate():
		character.status_component.start_of_turn()
	_free_dead()
	_update_facings()


## End of a side's turn: TURNS statuses lose their stacks.
func _end_of_turn_statuses(team: Array[Character]) -> void:
	for character in team:
		character.status_component.end_of_turn()


# ---------------------------------------------------------------------------
# Deaths and end of battle
# ---------------------------------------------------------------------------

func _on_character_died(character: Character) -> void:
	allies.erase(character)
	enemies.erase(character)
	character.hide()
	_dead.append(character)  # freed later, awaiting code may still hold a reference

	if character.is_ally():
		if _in_expedition:
			GameState.run.set_health(character.data.id, 0)  # down until a camp heals him
		deck.remove_cards_of(character)

	# Enemies that planned to act on the fallen character (hero hit, or enemy to buff) choose again
	for enemy in enemies:
		if enemy.intent != null and enemy.intent.target == character:
			_retarget_intent(enemy)
	intents_changed.emit()  # also hides the AOE circle of a dead enemy


func _free_dead() -> void:
	for character in _dead:
		if is_instance_valid(character):
			character.queue_free()
	_dead.clear()


## Called after every action. Returns true when the battle just ended.
## Victory comes from the objective; defeat is "all allies dead" or the objective failing.
func _check_battle_end() -> bool:
	objective_updated.emit()
	if objective.is_complete():
		_end_battle(true)
	elif allies.is_empty() or objective.is_failed():
		_end_battle(false)
	else:
		return false
	return true


func _end_battle(victory: bool) -> void:
	_set_phase(Phase.ENDED)
	_record_result(victory)
	battle_ended.emit(victory)


## Hands the outcome to the run: the heroes keep the health they have left, and the
## result is stored so the expedition screen can continue from it. Written right
## away (not on "Continue") so it survives closing the game on the victory screen.
func _record_result(victory: bool) -> void:
	if not _in_expedition:
		return
	var run := GameState.run
	for ally in allies:
		run.set_health(ally.data.id, ally.health.current_health)
	run.battle_result = RunState.BattleResult.VICTORY if victory else RunState.BattleResult.DEFEAT


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _set_phase(new_phase: Phase) -> void:
	phase = new_phase
	phase_changed.emit(phase)


func _set_actions(value: int) -> void:
	actions_left = value
	actions_changed.emit(actions_left)


func _set_mana(value: int) -> void:
	mana = maxi(value, 0)
	mana_changed.emit(mana)


## Moves several characters at once and waits until they arrive.
## moves: { Character: Vector2 destination }
func _move_characters(moves: Dictionary, duration: float) -> void:
	var tween: Tween = null
	for character in moves:
		if character.global_position.is_equal_approx(moves[character]):
			continue
		if tween == null:
			tween = create_tween().set_parallel(true)
		tween.tween_property(character, "global_position", moves[character], duration)
	if tween != null:
		await tween.finished


## Allies look at their closest enemy; enemies look at what they plan to do (their target
## or the AOE spot), or at the closest ally if they have no valid plan.
## Called after anything that moves or removes characters (spawn, card, enemy action).
## Attackers face their actual target while they strike.
func _update_facings() -> void:
	_face_closest(allies, enemies)
	for enemy in enemies:
		if _intent_is_valid(enemy):
			_face_intent(enemy)
		else:
			var closest := _closest_to(enemy, allies)
			if closest != null:
				enemy.face_towards(closest.global_position)


func _face_closest(team: Array[Character], opponents: Array[Character]) -> void:
	for character in team:
		var closest := _closest_to(character, opponents)
		if closest != null:
			character.face_towards(closest.global_position)


func _closest_to(character: Character, candidates: Array[Character]) -> Character:
	var best: Character = null
	var best_distance := INF
	for candidate in candidates:
		var distance := character.global_position.distance_squared_to(candidate.global_position)
		if distance < best_distance:
			best = candidate
			best_distance = distance
	return best
