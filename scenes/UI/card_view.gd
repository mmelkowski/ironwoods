extends Control
# Script of card UI to fill data

@onready var artwork: ColorRect = %Artwork
@onready var card_name: Label = %CardName
@onready var attack_value: Label = %AttackValue
@onready var card_type: Label = %CardType
@onready var card_description: Label = %CardDescription
@onready var mana_cost: Label = %ManaCost
@onready var mana_generation: Label = %ManaGeneration

signal clicked(card: CardInstance)

var card: CardInstance

func setup(new_card: CardInstance) -> void:
	card = new_card
	if is_node_ready():
		_update_display()

func _ready() -> void:
	if card:
		_update_display()

func set_playable(playable: bool) -> void:
	modulate = Color.WHITE if playable else Color(1, 1, 1, 0.5)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		print("[INFO]card_view.gd::_gui_input:: in fct")
		clicked.emit(card)

func _update_display():
	card_name.text = card.name
	if  card.critical:
		attack_value.text = ""
	elif card.critical:
		attack_value.text = str(card.critical_damage)
	else:
		attack_value.text = str(card.damage)
	card_type.text = card.card_type
	card_description.text = ""
	mana_cost.text = str(card.mana_cost)
	mana_generation.text = str(card.mana_generation)


# Potential signal to connect for updating UI after card buff
func _on_card_update():
	_update_display()
