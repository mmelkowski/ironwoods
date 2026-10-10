class_name Character
extends Node2D
## On-screen representation of one hero or enemy.
## Assign `data` in the inspector, or call setup(data) when spawning from code.

signal clicked(character: Character)  # for card targeting
signal died(character: Character)
signal statuses_changed

const TILE_SIZE := 32
const GROUP_ALLIES := &"allies"
const GROUP_ENEMIES := &"enemies"

@export var data: CharacterData

## Direction the character is facing, in radians (0 = right, PI = left).
## Updated by face_towards(). Cards use it for "behind the target" positioning.
var facing_angle: float = 0.0

## Enemies only: the ally this enemy will attack on its next turn.
var intent_target: Character

## Active statuses: StatusData -> stacks (Evasion is handled by HealthComponent).
var statuses: Dictionary = {}

@onready var health: HealthComponent = %HealthComponent
@onready var sprite: Sprite2D = %Sprite
@onready var health_bar: ProgressBar = %UI/HealthBar
@onready var armor_bar: ProgressBar = %UI/%ArmorBar
@onready var evasion_label: Label = %UI/%EvasionLabel
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


## Placeholder target highlight (tints the sprite). Swap for an outline or marker later.
func set_highlighted(on: bool) -> void:
	sprite.modulate = Color(1.0, 0.9, 0.4) if on else Color.WHITE


## Gives stacks of a status. Placeholder: only Evasion has an effect so far.
## TODO: tick TURNS statuses each turn, consume USES statuses, apply Stun/Bleeding.
func apply_status(status: StatusData, stacks: int) -> void:
	if status.id == &"evasion":
		health.add_evasion(stacks)
		return
	statuses[status] = statuses.get(status, 0) + stacks
	statuses_changed.emit()


## Turns the character towards a world position (e.g. the enemy it just attacked).
## Only stores the angle; the visual (flip_h when facing left) is up to you:
##   sprite.flip_h = cos(facing_angle) < 0.0
func face_towards(world_position: Vector2) -> void:
	facing_angle = global_position.direction_to(world_position).angle()


func _apply_data() -> void:
	# Team (groups let you do get_tree().get_nodes_in_group("enemies"))
	remove_from_group(GROUP_ALLIES)
	remove_from_group(GROUP_ENEMIES)
	add_to_group(GROUP_ALLIES if is_ally() else GROUP_ENEMIES)

	# Default facing: allies look right, enemies look left
	facing_angle = 0.0 if is_ally() else PI

	# Sprite cut out of the tileset
	var atlas := AtlasTexture.new()
	atlas.atlas = data.tileset
	atlas.region = Rect2(
		Vector2(data.tile_coords * TILE_SIZE),
		Vector2(data.size_in_tiles * TILE_SIZE))
	sprite.texture = atlas
	shape.radius = atlas.region.size.x / 2.0

	# Stats
	health.initialize(data.max_health)
	health.add_armor(data.starting_armor)
	health.add_evasion(data.starting_evasion)

	# Make sure the bars start in the right state (hidden when armor/evasion is 0)
	_on_armor_changed(health.armor)
	_on_evasion_changed(health.evasion)


func _on_health_changed(current: int, maximum: int) -> void:
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
