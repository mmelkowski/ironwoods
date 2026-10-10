class_name Hand
extends HBoxContainer
## Shows the player's hand as a row of card views.
## Attach to the HBoxContainer that holds the cards. It listens to the Battle,
## so battle.gd needs no UI code.
##
## Each card view scene (card_view_scene) must provide:
##   func setup(card: CardInstance)       - show this card
##   func set_playable(playable: bool)    - grey out / restore
##   func set_selected(selected: bool)    - raise / lower the card
##   signal clicked(card: CardInstance)   - emitted when the player clicks it
## and expose the CardInstance as a `card` variable.
##
## Every card view sits inside a "slot" (a plain Control). The container only
## lays out the slots, so a card can move freely inside its slot (raised when
## selected, and later hover effects) without the container putting it back.

## Emitted when a card view is clicked. The targeting controller connects here.
## The card may not be playable: check battle.can_play_card() before using it.
signal card_clicked(card: CardInstance)

## The Battle to listen to. If empty, the root of the scene this node was saved in is used.
@export var battle: Battle
@export var card_view_scene: PackedScene = preload("res://scenes/UI/card_view.tscn")

var _views: Array = []  # the card views, in hand order
var _selected_card: CardInstance


func _ready() -> void:
	if battle == null:
		battle = owner as Battle

	battle.deck.hand_changed.connect(_rebuild)
	# Anything that changes what is playable: unbind(1) drops the signal's argument.
	battle.actions_changed.connect(_refresh_playable.unbind(1))
	battle.mana_changed.connect(_refresh_playable.unbind(1))
	battle.phase_changed.connect(_refresh_playable.unbind(1))

	_rebuild()  # in case the first draw already happened


## Raises the view of this card and lowers all the others. null lowers everything.
func set_selected_card(card: CardInstance) -> void:
	_selected_card = card
	for view in _views:
		view.set_selected(view.card == card)


func _rebuild() -> void:
	# remove_child first: hand_changed can fire twice in one frame and
	# queue_free alone would leave the old slots in place until the frame ends.
	for slot in get_children():
		remove_child(slot)
		slot.queue_free()
	_views.clear()

	for card in battle.deck.hand:
		var view: Control = card_view_scene.instantiate()
		view.setup(card)
		view.clicked.connect(card_clicked.emit)

		var slot := Control.new()
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE  # clicks go to the card itself
		slot.add_child(view)
		add_child(slot)

		# The slot reserves the card's space in the row
		var card_size := view.get_combined_minimum_size()
		slot.custom_minimum_size = Vector2(
			maxf(card_size.x, view.size.x), maxf(card_size.y, view.size.y))

		view.set_selected(card == _selected_card)
		_views.append(view)

	_refresh_playable()


func _refresh_playable() -> void:
	for view in _views:
		view.set_playable(battle.can_play_card(view.card))
