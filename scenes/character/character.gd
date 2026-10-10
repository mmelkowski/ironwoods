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

# Intent cutout: size of the square cut around the target's head (CharacterData.head_position).
const INTENT_CUTOUT_SIZE := Vector2(16, 16)

@export var data: CharacterData

## Enemies only: the ally this enemy will attack on its next turn.
## Setting it updates the cutout above the enemy's head.
var intent_target: Character:
	set(value):
		intent_target = value
		_update_intent_icon()

## Active statuses: StatusData -> stacks (Evasion is handled by HealthComponent).
var statuses: Dictionary = {}

@onready var health: HealthComponent = %HealthComponent
@onready var sprite: Sprite2D = %Sprite
@onready var health_bar: ProgressBar = %UI/HealthBar
@onready var armor_bar: ProgressBar = %UI/%ArmorBar
@onready var evasion_label: Label = %UI/%EvasionLabel
@onready var intent_icon: Sprite2D = %IntentIcon
@onready var click_area: Area2D = %ClickArea
@onready var click_shape: CollisionShape2D = %ClickShape
@onready var shape := click_shape.shape as CircleShape2D


func _ready() -> void:
	health.health_changed.connect(_on_health_changed)
	health.armor_changed.connect(_on_armor_changed)
	health.evasion_changed.connect(_on_evasion_changed)
	health.died.connect(func(): died.emit(self))
	click_area.input_event.connect(_on_click_area_input_event)
	_update_intent_icon()  # hidden until an intent target is assigned

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


## Makes the character look at a world position by flipping the sprite.
## The art is drawn facing LEFT, so it is flipped when the target is on the right.
## Only the sprite is flipped, so the health bars stay readable.
func face_towards(world_position: Vector2) -> void:
	var dx := world_position.x - global_position.x
	if not is_zero_approx(dx):
		sprite.flip_h = dx > 0.0


## Shows the head of the intent target's sprite above this character,
## or hides the cutout when there is no target (allies never have one).
func _update_intent_icon() -> void:
	if not is_node_ready():
		return

	var source: AtlasTexture = null
	if intent_target != null:
		source = intent_target.sprite.texture as AtlasTexture
	if source == null:
		intent_icon.hide()
		return

	var crop := Rect2(
		source.region.position + intent_target.data.head_position - INTENT_CUTOUT_SIZE / 2.0,
		INTENT_CUTOUT_SIZE)
	var icon := AtlasTexture.new()
	icon.atlas = source.atlas
	icon.region = crop.intersection(source.region)  # never bleed into a neighbouring tile
	intent_icon.texture = icon
	intent_icon.show()


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
