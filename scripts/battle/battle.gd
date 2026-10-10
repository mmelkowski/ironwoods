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

@export var character_scene: PackedScene = preload("res://scenes/character/character.tscn")
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

@onready var allies_root: Node2D = %Allies
@onready var enemies_root: Node2D = %Enemies
@onready var ally_spawns: Node2D = %AllySpawns
@onready var enemy_spawns: Node2D = %EnemySpawns

## Living characters only. Dead ones are removed as soon as they die.
var allies: Array[Character] = []
var enemies: Array[Character] = []
var deck := CardDeck.new()

var phase: Phase = Phase.SETUP
var turn := 0
var actions_left := 0
var mana := 0  # shared by the whole team

var _dead: Array[Character] = []  # hidden, freed once the current action ends


func _ready() -> void:
	if not roster.is_empty():
		start_battle(roster)


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

func start_battle(characters: Array[CharacterData]) -> void:
	_spawn_roster(characters)
	_update_facings()
	deck.build_from(allies)
	for enemy in enemies:
		_assign_target(enemy)
	mana = 0
	turn = 0
	_start_player_turn()


func _spawn_roster(characters: Array[CharacterData]) -> void:
	print("battle.gd::_spawn_roster:: in fct")
	for data in characters:
		var is_ally := data.team == CharacterData.Team.ALLY
		var team := allies if is_ally else enemies

		var character: Character = character_scene.instantiate()
		character.setup(data)
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
	_set_phase(Phase.PLAYER_TURN)
	_set_actions(ACTIONS_PER_TURN)
	deck.draw_to_full()
	turn_started.emit(turn)


## Call this from the "End turn" button.
func end_player_turn() -> void:
	if phase != Phase.PLAYER_TURN:
		return
	await _run_enemy_turn()


func can_play_card(card: CardInstance) -> bool:
	return (
		phase == Phase.PLAYER_TURN
		and actions_left > 0
		and deck.hand.has(card)
		and allies.has(card.caster)
		and (card.data.card_type != CardData.Type.MANA or mana >= card.mana_cost)
	)


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
			_deal_damage(card, hit, killed)
			await _knock_back(card, hit)
	else:
		# Attack cards walk to the first pick, then every target is hit at once
		if attacks:
			await _approach(card, selected[0])
		_deal_damage(card, targets, killed)
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
		stand_at = card.data.get_approach_position(stand_at, target.global_position)
		if result.is_empty() or not result.back().is_equal_approx(stand_at):
			result.append(stand_at)
	return result


## The caster walks to the position this card needs around the target, looking at it.
func _approach(card: CardInstance, target: Character) -> void:
	var caster := card.caster
	var destination := card.data.get_approach_position(caster.global_position, target.global_position)
	caster.face_towards(target.global_position)  # look at the target while walking
	await _move_characters({caster: destination}, MOVE_TIME)
	caster.face_towards(target.global_position)  # a backstab ends up on the other side


## One hit on each target (dodged / absorbed by evasion and armor inside HealthComponent).
## Characters that die are added to `killed`.
func _deal_damage(card: CardInstance, targets: Array[Character], killed: Array[Character]) -> void:
	if card.damage <= 0:
		return
	var amount := roundi(card.damage * (CRIT_MULTIPLIER if card.critical else 1.0))
	for target in targets:
		var was_alive := not target.is_dead()
		target.health.take_damage(amount)
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
	for enemy in enemies.duplicate():
		if not enemies.has(enemy):
			continue
		await _enemy_attack(enemy)
		if _check_battle_end():
			return
		await get_tree().create_timer(ENEMY_ACTION_DELAY).timeout
	_start_player_turn()


## Placeholder attack: walk to the planned target and hit for the default damage.
func _enemy_attack(enemy: Character) -> void:
	if not allies.has(enemy.intent_target):
		_assign_target(enemy)
	var target := enemy.intent_target
	if target == null:
		return

	var destination := CardData.closest_in_range(
		enemy.global_position, target.global_position, enemy.data.attack_range)
	enemy.face_towards(target.global_position)
	await _move_characters({enemy: destination}, MOVE_TIME)
	enemy.face_towards(target.global_position)

	target.health.take_damage(enemy.data.attack_damage)
	_free_dead()
	_update_facings()
	_assign_target(enemy)  # telegraph the target for next turn


## Placeholder: random living ally.
func _assign_target(enemy: Character) -> void:
	enemy.intent_target = allies.pick_random() if not allies.is_empty() else null
	if enemy.intent_target != null:
		enemy.face_towards(enemy.intent_target.global_position)
	intents_changed.emit()


# ---------------------------------------------------------------------------
# Deaths and end of battle
# ---------------------------------------------------------------------------

func _on_character_died(character: Character) -> void:
	allies.erase(character)
	enemies.erase(character)
	character.hide()
	_dead.append(character)  # freed later, awaiting code may still hold a reference

	if character.is_ally():
		deck.remove_cards_of(character)
		for enemy in enemies:
			if enemy.intent_target == character:
				_assign_target(enemy)


func _free_dead() -> void:
	for character in _dead:
		if is_instance_valid(character):
			character.queue_free()
	_dead.clear()


## Objective check. Only "defeat all enemies" exists for now; hostage / chest
## objectives would replace _is_victory().
func _is_victory() -> bool:
	return enemies.is_empty()


func _is_defeat() -> bool:
	return allies.is_empty()


func _check_battle_end() -> bool:
	if _is_victory():
		_end_battle(true)
	elif _is_defeat():
		_end_battle(false)
	else:
		return false
	return true


func _end_battle(victory: bool) -> void:
	_set_phase(Phase.ENDED)
	battle_ended.emit(victory)


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


## Allies look at their closest enemy; enemies look at the ally they plan to attack
## (their intent_target), or at the closest ally if they have none.
## Called after anything that moves or removes characters (spawn, card, enemy attack).
## Attackers face their actual target while they strike.
func _update_facings() -> void:
	_face_closest(allies, enemies)
	for enemy in enemies:
		var focus: Character = enemy.intent_target if allies.has(enemy.intent_target) else _closest_to(enemy, allies)
		if focus != null:
			enemy.face_towards(focus.global_position)


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
