extends Control
# Script of card UI to fill data

@onready var artwork: ColorRect = %Artwork
@onready var card_name: Label = %CardName
@onready var attack_value: Label = %AttackValue
@onready var card_type: Label = %CardType
@onready var card_description: Label = %CardDescription
@onready var mana_cost: Label = %ManaCost
@onready var mana_generation: Label = %ManaGeneration
@onready var char_icon: Sprite2D = %CharIcon

const RAISE_HEIGHT := 24.0
const RAISE_TIME := 0.12
const UNPLAYABLE_TINT := Color(0.3, 0.3, 0.3, 1.0)
## On-screen size (px) of the owner's head icon, whatever the size of the cut.
const CHAR_ICON_SIZE := 32.0

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
	modulate = Color.WHITE if playable else UNPLAYABLE_TINT

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
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
			artwork.color = Color(0.51, 0.0, 0.188, 0.667)
		"1":
			card_type.text = "Support"
			artwork.color = Color(0.0, 0.321, 0.219, 0.667)
		"2":
			card_type.text = "Mana"
			artwork.color = Color(0.045, 0.112, 0.758, 0.667)
	card_description.text = card.card_description
	if card.mana_cost == 0:
		mana_cost.text = ""
	else:
		mana_cost.text = str(card.mana_cost)
	mana_generation.text = str(card.mana_generation)
	_update_char_icon()


## Shows the head of the hero who owns the card (hidden if there is none).
func _update_char_icon() -> void:
	var owner_hero: Character = card.caster
	if owner_hero == null or not is_instance_valid(owner_hero) or owner_hero.data == null:
		char_icon.visible = false
		return
	var head: Texture2D = owner_hero.data.get_head_texture()
	char_icon.texture = head
	char_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # keep pixel art sharp
	var head_size := head.get_size()
	var biggest := maxf(head_size.x, head_size.y)
	if biggest > 0.0:
		char_icon.scale = Vector2.ONE * (CHAR_ICON_SIZE / biggest)
	char_icon.visible = true


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
