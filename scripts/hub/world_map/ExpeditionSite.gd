@tool
class_name ExpeditionSite
extends Area2D
## One location of the world map. Instance expedition_site.tscn once per expedition, set its
## `expedition_id` and `texture`, and move it where you want on the map.
##
## WorldMap tells it how to look (configure):
##   UNLOCKED : the sprite as it is, hover tint, name label
##   TEASED   : the sprite as a black silhouette, label "???" (clicking shows how to unlock it)
##   HIDDEN   : not visible and not clickable
##
## Expected children (unique names): Sprite2D %Visual, CollisionShape2D %Collision, Label %NameLabel.
## The click area is sized from the texture automatically.

signal selected(site: ExpeditionSite)

enum State { HIDDEN, TEASED, UNLOCKED }

const HOVER_COLOR := Color(1.25, 1.25, 1.25)
const TEASED_COLOR := Color(0.0, 0.0, 0.0, 1.0)
const SELECTED_SCALE := 1.1

## The id of the ExpeditionData this location stands for.
@export var expedition_id: StringName
## The picture of the location.
@export var texture: Texture2D:
	set(value):
		texture = value
		_apply_texture()
## Where the name appears, from the center of the location.
@export var label_offset := Vector2(0, 60)

@onready var visual: Sprite2D = %Visual
@onready var collision: CollisionShape2D = %Collision
@onready var name_label: Label = %NameLabel

var expedition: ExpeditionData
var state := State.UNLOCKED
var _hovered := false
var _selected := false
var _interactive := true
var _base_scale := Vector2.ONE


func _ready() -> void:
	_base_scale = visual.scale
	_apply_texture()
	name_label.hide()
	if Engine.is_editor_hint():
		return
	add_to_group(&"expedition_sites")
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	input_event.connect(_on_input_event)


## Called by WorldMap: which expedition this is, how it appears, and whether it was completed.
func configure(new_expedition: ExpeditionData, new_state: State, completed: bool) -> void:
	expedition = new_expedition
	state = new_state
	match state:
		State.HIDDEN:
			name_label.text = ""
		State.TEASED:
			visual.self_modulate = TEASED_COLOR
			name_label.text = "???"
		State.UNLOCKED:
			visual.self_modulate = Color.WHITE
			name_label.text = expedition.display_name + (" (done)" if completed else "")
	name_label.position = label_offset + Vector2(-name_label.get_minimum_size().x / 2.0, 0.0)
	_refresh()


func set_selected(value: bool) -> void:
	_selected = value
	_refresh()


## Off while a menu is open on top of the map.
func set_interactive(value: bool) -> void:
	_interactive = value
	if not value:
		_hovered = false
	_refresh()


func _refresh() -> void:
	visible = state != State.HIDDEN
	input_pickable = _interactive and state != State.HIDDEN
	visual.scale = _base_scale * (SELECTED_SCALE if _selected else 1.0)
	visual.modulate = HOVER_COLOR if (_hovered and state == State.UNLOCKED) else Color.WHITE

	name_label.visible = true if state != State.HIDDEN else false


func _apply_texture() -> void:
	if not is_node_ready():
		return
	visual.texture = texture
	var size := Vector2(64.0, 64.0)
	if texture != null:
		size = texture.get_size() * visual.scale.abs()
	var shape := RectangleShape2D.new()
	shape.size = size
	collision.shape = shape



func _on_mouse_entered() -> void:
	_hovered = true
	_refresh()


func _on_mouse_exited() -> void:
	_hovered = false
	_refresh()


func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if state == State.HIDDEN or not _interactive:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		selected.emit(self)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		pass
		#print("Global click detected anywhere on screen!")
