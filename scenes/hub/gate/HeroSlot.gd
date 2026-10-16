class_name HeroSlot
extends PanelContainer
## One of the team spots: name above, full sprite, stats below.
##
## Scene (hero_slot.tscn):
##   HeroSlot (PanelContainer, this script)
##   └── VBoxContainer
##       ├── NameLabel   (Label, centered)
##       ├── SpriteRect  (TextureRect: Expand Mode = Ignore Size, Stretch Mode = Keep Aspect
##       │                Centered, Size Flags Vertical = Expand + Fill)
##       └── StatsLabel  (Label, centered)
## NameLabel, SpriteRect and StatsLabel use "Access as Unique Name".

signal clicked(slot: HeroSlot)

const EMPTY_TINT := Color(1, 1, 1, 0.35)

@onready var name_label: Label = %NameLabel
@onready var sprite_rect: TextureRect = %SpriteRect
@onready var stats_label: Label = %StatsLabel


func _ready() -> void:
	# Every spot takes an equal share of the row, empty or not,
	# so nothing moves when a hero is picked or removed.
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_stretch_ratio = 1.0

	# A label's minimum width follows its text. Without this, a long name or
	# stat line would make its column wider than the others.
	for label in [name_label, stats_label]:
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS


## null empties the slot.
func set_hero(hero: CharacterData) -> void:
	if hero == null:
		name_label.text = "Empty"
		sprite_rect.texture = null
		stats_label.text = ""
		modulate = EMPTY_TINT
		return

	name_label.text = hero.display_name
	sprite_rect.texture = hero.get_sprite_texture()
	stats_label.text = "Health: %d\nArmor: %d\nEvasion: %d\nCards: %d" % [
		hero.max_health, hero.starting_armor, hero.starting_evasion, hero.deck.size()]
	modulate = Color.WHITE


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(self)
