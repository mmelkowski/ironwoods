class_name HubLocation
extends Area2D
## A clickable place of the hub: the main gate, the tavern, the forge...
##
## Scene: Area2D (this script)
##        ├── CollisionShape2D   <- the clickable area
##        └── Sprite2D           <- the building (assign it to `visual`)
##
## Clicking it emits `activated`. The Hub then opens `menu_scene` (if any).
## A place with no menu (a door that starts a cutscene...) can be handled by
## listening to the Hub's `location_activated` signal instead.

signal activated(location: HubLocation)

const GROUP := &"hub_locations"
const HOVER_TINT := Color(1.25, 1.25, 1.25)
const DISABLED_TINT := Color(0.45, 0.45, 0.45)

## Stable name for code ("gate", "tavern", "forge"...).
@export var location_id: StringName
## Shown above the building when the mouse is over it.
@export var display_name: String = ""
## The menu opened on click. Its root must extend HubMenu.
@export var menu_scene: PackedScene
## Always shown, even if the player hasn't unlocked it (decoration, a person to talk to...).
## Otherwise the place stays hidden until its building is built.
@export var always_unlocked: bool = false
## A disabled place is greyed out and can't be opened (locked until a story step...).
@export var enabled: bool = true:
	set(value):
		enabled = value
		_refresh_look()
## The node tinted on hover (usually the Sprite2D). If empty, the whole place is tinted.
@export var visual: CanvasItem
## Where the name appears, relative to this node.
@export var label_offset: Vector2 = Vector2(0, -40)

var _hovered := false
var _label: Label
var _unlocked := true      # hidden and not clickable until the player unlocks it
var _interactive := true   # turned off by the Hub while a menu is open


func _ready() -> void:
	add_to_group(GROUP)

	_label = Label.new()
	_label.text = display_name
	_label.visible = false
	_label.z_index = 10
	_label.position = label_offset - Vector2(_label.get_minimum_size().x / 2.0, 0.0)  # centered
	add_child(_label)

	mouse_entered.connect(_set_hovered.bind(true))
	mouse_exited.connect(_set_hovered.bind(false))
	input_event.connect(_on_input_event)
	_refresh_look()
	_update_pickable()


## The Hub turns this off while a menu is open so the town behind can't be clicked.
func set_interactive(interactive: bool) -> void:
	_interactive = interactive
	if not interactive:
		_set_hovered(false)
	_update_pickable()


## The Hub shows the place once the player has unlocked it, and hides it before.
func set_unlocked(unlocked: bool) -> void:
	_unlocked = unlocked or always_unlocked
	visible = _unlocked
	if not _unlocked:
		_set_hovered(false)
	_update_pickable()


func _update_pickable() -> void:
	input_pickable = _unlocked and _interactive


func _set_hovered(hovered: bool) -> void:
	_hovered = hovered
	_label.visible = hovered and display_name != ""
	_refresh_look()


func _refresh_look() -> void:
	if not is_node_ready():
		return
	var target: CanvasItem = visual if visual != null else self
	if not enabled:
		target.modulate = DISABLED_TINT
	elif _hovered:
		target.modulate = HOVER_TINT
	else:
		target.modulate = Color.WHITE


func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if not enabled:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		activated.emit(self)
