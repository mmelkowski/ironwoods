class_name MoveController
extends Node
## Turns "click a hero, then click where it goes" into battle.do_move().
## Add it as a node in the battle scene and assign `hand` in the inspector
## (`overlay` and `targeting` are found by themselves when left empty).
##
## 1st click: a hero is selected (the team must have a move left: Battle.moves_left).
## 2nd click: on an empty spot, the hero walks there (green circle = free, red = blocked).
##            On a character (ally or enemy), that character is chosen to be pushed.
## 3rd click (push only): confirms the angle. The cone is centered on the line hero -> target and
##            the arrow follows the mouse inside it, so the mouse doesn't need to be precise.
## Right click goes back one step, Esc (or clicking the hero again, or a card) cancels.
## Nothing happens while a card waits for its targets: the TargetingController has priority.
##
## All the rules (what is valid, damage) live in Battle. This script only handles input and the preview.

enum Step { IDLE, MOVER, AIM }

const VALID_COLOR := Color(0.3, 0.9, 0.4)    # where the hero will stand
const INVALID_COLOR := Color(0.9, 0.3, 0.3)  # blocked spot, or a push that is refused
const ALLY_COLOR := Color(0.4, 0.7, 1.0)     # area of every ally
const ENEMY_COLOR := Color(1.0, 0.55, 0.2)   # area of every enemy
const PUSH_COLOR := Color(1.0, 0.85, 0.3)    # cone and end of the slide
const CONE_EXTRA_LENGTH := 60.0              # the cone reaches this far past the end of the slide

## If empty, the root of the scene this node was saved in is used.
@export var battle: Battle
## Selecting a card cancels the move in progress.
@export var hand: Hand
## Draws circles, cone and arrow. If empty, the first TargetingOverlay found in the battle is used.
@export var overlay: TargetingOverlay
## If empty, the first TargetingController found in the battle is used.
@export var targeting: TargetingController

var _step := Step.IDLE
var _mover: Character
var _victim: Character
var _tinted: Array = []  # characters currently highlighted
var _last_mouse := Vector2.INF


func _ready() -> void:
	if battle == null:
		battle = owner as Battle
	if overlay == null:
		overlay = _find_node(battle, TargetingOverlay) as TargetingOverlay
	if targeting == null:
		targeting = _find_node(battle, TargetingController) as TargetingController
	if overlay == null:
		push_warning("MoveController: no TargetingOverlay found, the preview won't be drawn.")

	if hand != null:
		hand.card_clicked.connect(_on_card_clicked.unbind(1))
	battle.phase_changed.connect(_on_phase_changed.unbind(1))
	battle.moves_changed.connect(_on_moves_changed.unbind(1))
	set_process(false)


func cancel() -> void:
	_reset()


func _on_card_clicked() -> void:
	_reset()


func _on_phase_changed() -> void:
	if battle.phase != Battle.Phase.PLAYER_TURN:  # card resolving, enemy turn, battle end...
		_reset()


func _on_moves_changed() -> void:
	if _step != Step.IDLE and (not is_instance_valid(_mover) or not battle.can_move(_mover)):
		_reset()


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_on_left_click()
		elif event.button_index == MOUSE_BUTTON_RIGHT and _step != Step.IDLE:
			_go_back()
			get_viewport().set_input_as_handled()
	elif _step != Step.IDLE and event.is_action_pressed("ui_cancel"):
		_reset()
		get_viewport().set_input_as_handled()


func _on_left_click() -> void:
	if battle.phase != Battle.Phase.PLAYER_TURN:
		return
	if targeting != null and targeting.has_selection():
		return  # a card is being aimed: its clicks are not ours

	var mouse := battle.get_global_mouse_position()
	var clicked := battle.get_character_at(mouse)
	match _step:
		Step.IDLE:
			if clicked != null and battle.can_move(clicked):
				_mover = clicked
				_step = Step.MOVER
				set_process(true)
				_refresh()
		Step.MOVER:
			if clicked == _mover:
				_reset()
			elif clicked != null:
				_victim = clicked  # the push: now aim with the mouse
				_step = Step.AIM
				_refresh()
			else:
				var walk := battle.plan_walk(_mover, mouse)
				if walk.valid:
					_commit(walk)
		Step.AIM:
			var push := battle.plan_push(_mover, _victim, mouse)
			if push.valid:
				_commit(push)


func _go_back() -> void:
	if _step == Step.AIM:
		_victim = null
		_step = Step.MOVER
		_refresh()
	else:
		_reset()


func _commit(plan: MovePlan) -> void:
	_reset()
	await battle.do_move(plan)


func _reset() -> void:
	if _step == Step.IDLE:
		return
	_step = Step.IDLE
	_mover = null
	_victim = null
	_untint_all()
	set_process(false)
	# If a card was just selected, the overlay already shows its preview: leave it alone
	if overlay != null and (targeting == null or not targeting.has_selection()):
		overlay.clear()


# ---------------------------------------------------------------------------
# Preview
# ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if battle.get_global_mouse_position() != _last_mouse:
		_refresh()


func _refresh() -> void:
	if _step == Step.IDLE:
		return
	if not is_instance_valid(_mover) or (_step == Step.AIM and not is_instance_valid(_victim)):
		_reset()
		return

	var mouse := battle.get_global_mouse_position()
	_last_mouse = mouse
	_untint_all()
	_tint(_mover)

	var circles: Array[Dictionary] = []
	for ally in battle.allies:
		circles.append(_area_of(ally, ALLY_COLOR))
	for enemy in battle.enemies:
		circles.append(_area_of(enemy, ENEMY_COLOR))
	var badges: Array[Dictionary] = []
	var cones: Array[Dictionary] = []
	var arrows: Array[Dictionary] = []

	if _step == Step.MOVER:
		_preview_walk(mouse, circles)
	else:
		_preview_push(mouse, circles, badges, cones, arrows)

	if overlay != null:
		overlay.show_preview(circles, PackedVector2Array(), badges, cones, arrows)


## The area of a character: ring only, so the free space stays readable.
func _area_of(character: Character, color: Color) -> Dictionary:
	return {
		"center": character.global_position,
		"radius": character.shape.radius,
		"color": color,
		"outline_only": true,
	}


func _preview_walk(mouse: Vector2, circles: Array[Dictionary]) -> void:
	var hover := battle.get_character_at(mouse)
	if hover != null:
		if hover != _mover:
			_tint(hover)  # a click here chooses it for a push
		return
	var plan := battle.plan_walk(_mover, mouse)
	circles.append({
		"center": mouse,
		"radius": _mover.shape.radius,
		"color": VALID_COLOR if plan.valid else INVALID_COLOR,
	})


func _preview_push(
		mouse: Vector2, circles: Array[Dictionary], badges: Array[Dictionary],
		cones: Array[Dictionary], arrows: Array[Dictionary]) -> void:
	var plan := battle.plan_push(_mover, _victim, mouse)
	var color := VALID_COLOR if plan.valid else INVALID_COLOR
	_tint(_victim)

	# Where the hero will stand, and where the victim will end up
	circles.append({"center": plan.destination, "radius": _mover.shape.radius, "color": color})
	circles.append({
		"center": plan.push_end, "radius": _victim.shape.radius,
		"color": PUSH_COLOR, "outline_only": true,
	})

	# The cone of the possible angles and the arrow of the chosen one
	var victim_position := _victim.global_position
	var reach := Battle.PUSH_DISTANCE + _victim.shape.radius
	cones.append({
		"apex": victim_position, "axis": plan.axis, "half_angle": Battle.PUSH_CONE_HALF_ANGLE,
		"length": reach + CONE_EXTRA_LENGTH, "color": PUSH_COLOR,
	})
	arrows.append({"from": victim_position, "to": victim_position + plan.direction * reach, "color": color})

	# The collision, with the damage each side will take
	if plan.collided != null:
		_tint(plan.collided)
		badges.append({"at": victim_position, "text": "-%d" % plan.damage_to_victim})
		if plan.damage_to_other > 0:
			badges.append({"at": plan.collided.global_position, "text": "-%d" % plan.damage_to_other})


func _tint(character: Character) -> void:
	character.set_highlighted(true)
	_tinted.append(character)


func _untint_all() -> void:
	for character in _tinted:
		if is_instance_valid(character):
			character.set_highlighted(false)
	_tinted.clear()


func _find_node(node: Node, type: Variant) -> Node:
	for child in node.get_children():
		if is_instance_of(child, type):
			return child
		var found := _find_node(child, type)
		if found != null:
			return found
	return null
