class_name Hand
extends HBoxContainer
## Shows the player's hand as a row of card views.
## Attach to the HBoxContainer that holds the cards. It listens to the Battle,
## so battle.gd needs no UI code.
##
## Each card view scene (card_view_scene) must provide:
##   func setup(card: CardInstance)       - show this card
##   func set_playable(playable: bool)    - grey out / restore
##   signal clicked(card: CardInstance)   - emitted when the player clicks it
## and expose the CardInstance as a `card` variable.

## Emitted when a card view is clicked. The targeting controller connects here.
## The card may not be playable: check battle.can_play_card() before using it.
signal card_clicked(card: CardInstance)

## The Battle to listen to. If empty, the root of the scene this node was saved in is used.
@export var battle: Battle
@export var card_view_scene: PackedScene = preload("res://scenes/UI/card_view.tscn")


func _ready() -> void:
	if battle == null:
		battle = owner as Battle

	battle.deck.hand_changed.connect(_rebuild)
	# Anything that changes what is playable: unbind(1) drops the signal's argument.
	battle.actions_changed.connect(_refresh_playable.unbind(1))
	battle.mana_changed.connect(_refresh_playable.unbind(1))
	battle.phase_changed.connect(_refresh_playable.unbind(1))

	_rebuild()  # in case the first draw already happened


func _rebuild() -> void:
	# remove_child first: hand_changed can fire twice in one frame and
	# queue_free alone would leave the old views in place until the frame ends.
	for view in get_children():
		remove_child(view)
		view.queue_free()

	for card in battle.deck.hand:
		var view := card_view_scene.instantiate()
		view.setup(card)
		view.clicked.connect(card_clicked.emit)
		add_child(view)

	_refresh_playable()


func _refresh_playable() -> void:
	for view in get_children():
		view.set_playable(battle.can_play_card(view.card))
