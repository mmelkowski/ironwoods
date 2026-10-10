class_name TargetingController
extends Node
## Turns "click a card, then click its target(s)" into battle.play_card().
## Add it as a node in the battle scene and assign `hand` (and `overlay`) in the inspector.
##
## - SINGLE / AOE cards: the first click selects a target (an AOE also shows its
##   radius), a second click on the same target confirms. Clicking another target
##   changes the selection. Enter / Space also confirms.
## - CHAINED cards: click targets one by one. The same character can be picked
##   several times. The card plays by itself once max_targets are picked.
## - MULTIPLE cards: click targets one by one, then confirm with Enter / Space
##   (or call confirm_selection() from a button). Click a picked target to undo it.
## - Right click undoes the last pick (or cancels if there are none).
##   Esc, or clicking the selected card again, cancels everything.
##
## All the rules (who can be picked) live in Battle. This script only handles input and the preview.

const DESTINATION_COLOR := Color(0.3, 0.9, 0.4)  # translucent green: where the caster will stand

## If empty, the root of the scene this node was saved in is used.
@export var battle: Battle
@export var hand: Hand
## Draws circles, lines and numbers. If empty, the first TargetingOverlay found in the battle is used.
@export var overlay: TargetingOverlay
## MULTIPLE cards: play as soon as the maximum number of targets is picked,
## without pressing confirm. (CHAINED cards always do.)
@export var auto_confirm_when_full: bool = false

var _card: CardInstance                  # the card waiting for its targets
var _picks: Array[Character] = []        # targets picked so far, in order (may repeat in a chain)
var _pickable: Array[Character] = []     # characters that can be clicked next
var _tinted: Array[Character] = []       # characters currently highlighted


func _ready() -> void:
	if battle == null:
		battle = owner as Battle
	if overlay == null:
		overlay = _find_overlay(battle)
	if overlay == null:
		push_warning("TargetingController: no TargetingOverlay found, circles and lines won't be drawn.")

	hand.card_clicked.connect(_on_card_clicked)
	battle.character_clicked.connect(_on_character_clicked)
	battle.phase_changed.connect(_clear_selection.unbind(1))  # enemy turn, battle end...


func confirm_selection() -> void:
	if _card == null or _picks.is_empty():
		return

	var card := _card
	var picks: Array[Character] = []
	picks.append_array(_picks)
	if not battle.is_valid_selection(card, picks):
		return

	_clear_selection()
	await battle.play_card(card, picks)


func cancel_selection() -> void:
	_clear_selection()


func _on_card_clicked(card: CardInstance) -> void:
	var was_selected := card == _card
	_clear_selection()
	if was_selected or not battle.can_play_card(card):
		return  # clicking the selected card again cancels it

	# Self-targeted cards need no target: play immediately
	if card.data.target_team == CardData.TargetTeam.SELF:
		var picks: Array[Character] = [card.caster]
		await battle.play_card(card, picks)
		return

	_card = card
	_refresh_preview()


func _on_character_clicked(character: Character) -> void:
	if _card == null:
		return

	var max_picks := battle.get_max_picks(_card)

	# SINGLE / AOE: the first click selects, clicking the selected target again confirms.
	# Clicking another target changes the selection.
	if max_picks == 1:
		if _picks.has(character):
			confirm_selection()
		elif _pickable.has(character):
			_picks.clear()
			_picks.append(character)
			_refresh_preview()
		return

	# MULTIPLE / CHAINED: pick several targets
	if _picks.has(character) and not battle.allows_repeat_picks(_card):
		_picks.erase(character)  # click a picked target again to undo it
	elif _pickable.has(character):
		_picks.append(character)
	else:
		return
	_refresh_preview()

	if _picks.size() >= max_picks and _plays_when_full(_card):
		confirm_selection()


## MULTIPLE / CHAINED cards that don't wait for the confirm key once the last target is picked.
func _plays_when_full(card: CardInstance) -> bool:
	return card.data.target_type == CardData.TargetType.CHAINED or auto_confirm_when_full


func _unhandled_input(event: InputEvent) -> void:
	if _card == null:
		return
	var right_click: bool = (
		event is InputEventMouseButton
		and event.pressed
		and event.button_index == MOUSE_BUTTON_RIGHT
	)
	if event.is_action_pressed("ui_cancel"):
		cancel_selection()
	elif right_click:
		if _picks.is_empty():
			cancel_selection()
		else:
			_picks.pop_back()
			_refresh_preview()
	elif event.is_action_pressed("ui_accept"):
		confirm_selection()


# ---------------------------------------------------------------------------
# Preview
# ---------------------------------------------------------------------------

func _refresh_preview() -> void:
	# SINGLE / AOE keep every valid target clickable so the selection can be changed
	var single := battle.get_max_picks(_card) == 1
	var basis: Array[Character] = []
	if not single:
		basis = _picks
	_pickable = battle.get_pickable_targets(_card, basis)

	# Highlight: who can be clicked, or once a SINGLE / AOE target is selected, who will be hit
	_set_highlight(_tinted, false)
	_tinted = []  # a copy: _picks and _pickable change while the highlight must stay accurate
	if single and not _picks.is_empty():
		_tinted.append_array(battle.get_affected_targets(_card, _picks))
	else:
		_tinted.append_array(_pickable)
	_set_highlight(_tinted, true)

	if overlay == null:
		return

	var data := _card.data
	var circles: Array[Dictionary] = []
	var badges: Array[Dictionary] = []
	var line := PackedVector2Array()

	match data.target_type:
		CardData.TargetType.AOE:
			# The area the attack will cover, around the selected target
			if not _picks.is_empty():
				circles.append({
					"center": _picks[0].global_position,
					"radius": data.aoe_radius,
				})
		CardData.TargetType.MULTIPLE:
			# Range around the caster
			if data.select_radius > 0.0:
				circles.append({
					"center": _card.caster.global_position,
					"radius": data.select_radius,
				})
		CardData.TargetType.CHAINED:
			# Where the chain can jump next, around the last pick
			if not _picks.is_empty() and _picks.size() < battle.get_max_picks(_card):
				circles.append({
					"center": _picks.back().global_position,
					"radius": data.chain_radius,
				})

	# Where the caster will stand after its move (one circle per step of a chain),
	# drawn the size of the caster
	for destination in battle.get_approach_positions(_card, _picks):
		circles.append({
			"center": destination,
			"radius": _card.caster.shape.radius,
			"color": DESTINATION_COLOR,
		})

	# Numbered badges and the chain line (not needed for single-pick cards).
	# One badge per character: a character picked twice in a chain shows "1,3".
	if not single:
		var numbers := {}  # Character -> Array of pick numbers
		for i in _picks.size():
			var character := _picks[i]
			if not numbers.has(character):
				numbers[character] = []
			numbers[character].append(str(i + 1))
			if data.target_type == CardData.TargetType.CHAINED:
				line.append(character.global_position)
		for character in numbers:
			badges.append({"at": character.global_position, "text": ",".join(numbers[character])})

	overlay.show_preview(circles, line, badges)


func _set_highlight(characters: Array[Character], on: bool) -> void:
	for character in characters:
		if is_instance_valid(character):
			character.set_highlighted(on)


func _clear_selection() -> void:
	_set_highlight(_tinted, false)
	_tinted.clear()
	_pickable.clear()
	_picks.clear()
	_card = null
	if overlay != null:
		overlay.clear()


func _find_overlay(node: Node) -> TargetingOverlay:
	for child in node.get_children():
		if child is TargetingOverlay:
			return child
		var found := _find_overlay(child)
		if found != null:
			return found
	return null
