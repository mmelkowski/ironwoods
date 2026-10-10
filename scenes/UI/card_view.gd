extends Control
# Script of card UI to fill data

@onready var artwork: ColorRect = %Artwork
@onready var card_name: Label = %CardName
@onready var attack_value: Label = %AttackValue
@onready var card_type: Label = %CardType
@onready var card_description: Label = %CardDescription
@onready var mana_cost: Label = %ManaCost
@onready var mana_generation: Label = %ManaGeneration

const RAISE_HEIGHT := 24.0
const RAISE_TIME := 0.12

var _raise_tween: Tween

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
	if card.damage == 0:
		attack_value.text = ""
	elif card.critical:
		attack_value.text = str(card.critical_damage)
	else:
		attack_value.text = str(card.damage)
	match card.card_type:
		"0":
			card_type.text = "Attack"
		"1":
			card_type.text = "Support"
		"2":
			card_type.text = "Mana"
	card_description.text = card.card_description
	if card.mana_cost == 0:
		mana_cost.text = ""
	else:
		mana_cost.text = str(card.mana_cost)
	mana_generation.text = str(card.mana_generation)


# Potential signal to connect for updating UI after card buff
func _on_card_update():
	_update_display()


func set_selected(selected: bool) -> void:
	var target_y := -RAISE_HEIGHT if selected else 0.0
	if not is_inside_tree():
		position.y = target_y
		return
	if _raise_tween:
		_raise_tween.kill()
	_raise_tween = create_tween()
	_raise_tween.tween_property(self, "position:y", target_y, RAISE_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
