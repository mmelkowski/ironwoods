class_name TargetingController
extends Node
## Turns "click a card, then click a target" into battle.play_card().
## Add it as a node in the battle scene and assign `hand` in the inspector.
##
## Supported now: SINGLE and AOE cards (one pick) and self-targeted cards (played at once).
## TODO: MULTIPLE / CHAINED cards need a multi-pick + confirm step.

## If empty, the root of the scene this node was saved in is used.
@export var battle: Battle
@export var hand: Hand

var _card: CardInstance                  # the card waiting for a target
var _candidates: Array[Character] = []   # characters currently highlighted


func _ready() -> void:
	if battle == null:
		battle = owner as Battle
	hand.card_clicked.connect(_on_card_clicked)
	battle.character_clicked.connect(_on_character_clicked)
	battle.phase_changed.connect(_clear_selection.unbind(1))  # enemy turn, battle end...


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

	if card.data.target_type in [CardData.TargetType.MULTIPLE, CardData.TargetType.CHAINED]:
		push_warning("TargetingController: multi-target cards are not supported yet.")
		return

	_card = card
	_candidates = battle.get_valid_targets(card)
	for character in _candidates:
		character.set_highlighted(true)


func _on_character_clicked(character: Character) -> void:
	if _card == null or not _candidates.has(character):
		return

	var card := _card
	var picks: Array[Character] = [character]
	if not battle.is_valid_selection(card, picks):
		return

	_clear_selection()
	await battle.play_card(card, picks)


func _unhandled_input(event: InputEvent) -> void:
	if _card == null:
		return
	var right_click: bool = (
		event is InputEventMouseButton
		and event.pressed
		and event.button_index == MOUSE_BUTTON_RIGHT
	)
	if event.is_action_pressed("ui_cancel") or right_click:
		_clear_selection()


func _clear_selection() -> void:
	for character in _candidates:
		if is_instance_valid(character):
			character.set_highlighted(false)
	_candidates.clear()
	_card = null
