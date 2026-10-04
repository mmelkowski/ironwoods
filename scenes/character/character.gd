class_name Character
extends Node2D
## On-screen representation of one hero or enemy.
## Assign `data` in the inspector, or call setup(data) when spawning from code.

signal clicked(character: Character)  # for card targeting
signal died(character: Character)

const TILE_SIZE := 32
const GROUP_ALLIES := &"allies"
const GROUP_ENEMIES := &"enemies"

@export var data: CharacterData

@onready var health: HealthComponent = %HealthComponent
@onready var sprite: Sprite2D = %Sprite
#@onready var name_label: Label = %NameLabel
@onready var UI: Control = %UI
@onready var health_bar: ProgressBar = %UI/HealthBar
@onready var armor_bar: ProgressBar = %UI/ArmorBar
@onready var evasion_label: Label = %UI/EvasionLabel
@onready var click_area: Area2D = %ClickArea
@onready var click_shape: CollisionShape2D = %ClickShape
@onready var shape := click_shape.shape as CircleShape2D

func _ready() -> void:
	health.health_changed.connect(_on_health_changed)
	health.armor_changed.connect(_on_armor_changed)
	health.evasion_changed.connect(_on_evasion_changed)
	health.died.connect(func(): died.emit(self))
	click_area.input_event.connect(_on_click_area_input_event)

	if data:
		_apply_data()


## Use this when spawning from code:
##   var c = character_scene.instantiate()
##   c.setup(preload("res://data/characters/wolf.tres"))
##   add_child(c)
func setup(new_data: CharacterData) -> void:
	data = new_data
	if is_node_ready():
		_apply_data()


func is_ally() -> bool:
	return data.team == CharacterData.Team.ALLY


func is_dead() -> bool:
	return health.is_dead()


func _apply_data() -> void:
	# Team (groups let you do get_tree().get_nodes_in_group("enemies"))
	remove_from_group(GROUP_ALLIES)
	remove_from_group(GROUP_ENEMIES)
	add_to_group(GROUP_ALLIES if is_ally() else GROUP_ENEMIES)

	# Sprite cut out of the tileset
	var atlas := AtlasTexture.new()
	atlas.atlas = data.tileset
	atlas.region = Rect2(
		Vector2(data.tile_coords * TILE_SIZE),
		Vector2(data.size_in_tiles * TILE_SIZE))
	sprite.texture = atlas
	shape.radius = atlas.region.size.x / 2.0

	# Stats
	#name_label.text = data.display_name
	health.initialize(data.max_health)
	health.add_armor(data.starting_armor)
	health.add_evasion(data.starting_evasion)

	# Make sure the bars start in the right state (hidden when armor/evasion is 0)
	_on_armor_changed(health.armor)
	_on_evasion_changed(health.evasion)


func _on_health_changed(current: int, maximum: int) -> void:
	print("in fct _on_health_changed", current, maximum)
	health_bar.max_value = maximum
	health_bar.value = current
	armor_bar.max_value = maximum  # armor bar is drawn relative to max health


func _on_armor_changed(current: int) -> void:
	armor_bar.visible = current > 0
	armor_bar.value = current


func _on_evasion_changed(stacks: int) -> void:
	evasion_label.visible = stacks > 0
	evasion_label.text = "Evasion x%d" % stacks


func _on_click_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(self)
