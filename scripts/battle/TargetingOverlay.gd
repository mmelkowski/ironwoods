class_name TargetingOverlay
extends Node2D
## Draws the targeting preview. It only draws what it is told to, the
## TargetingController decides what to show.
##   - range circles: drawn UNDER the characters (this node)
##   - chain line and pick numbers: drawn OVER the characters (a child node
##     with a higher z_index, created in _ready)
##
## Scene setup: add this node to the battle scene AFTER the TileMapLayer and
## BEFORE Allies / Enemies, so circles are over the floor but under the sprites.
## Keep its position at (0, 0). All positions passed in are global.

const DEFAULT_COLOR := Color(1.0, 0.85, 0.3)  # circles without a "color" key
const FILL_ALPHA := 0.18
const EDGE_ALPHA := 0.7
const LINE_COLOR := Color(1.0, 0.85, 0.3, 0.9)
const BADGE_COLOR := Color(0.1, 0.1, 0.1, 0.85)
const BADGE_OFFSET := Vector2(12, -12)  # from the character's position (top-right of a 32px sprite)
const BADGE_HEIGHT := 14.0
const FONT_SIZE := 10

var _circles: Array[Dictionary] = []  # { "center": Vector2, "radius": float, "color": Color (optional) }
var _line := PackedVector2Array()
var _badges: Array[Dictionary] = []   # { "at": Vector2, "text": String }
var _top: Node2D


func _ready() -> void:
	_top = Node2D.new()
	_top.z_index = 1  # above the characters, which are at 0
	add_child(_top)
	_top.draw.connect(_draw_top)


func show_preview(circles: Array[Dictionary], line: PackedVector2Array, badges: Array[Dictionary]) -> void:
	_circles = circles
	_line = line
	_badges = badges
	queue_redraw()
	_top.queue_redraw()


func clear() -> void:
	show_preview([], PackedVector2Array(), [])


func _draw() -> void:
	for circle in _circles:
		var center := to_local(circle["center"])
		var color: Color = circle.get("color", DEFAULT_COLOR)
		draw_circle(center, circle["radius"], Color(color, FILL_ALPHA))
		draw_arc(center, circle["radius"], 0.0, TAU, 64, Color(color, EDGE_ALPHA), 1.0, true)


func _draw_top() -> void:
	if _line.size() >= 2:
		var points := PackedVector2Array()
		for point in _line:
			points.append(_top.to_local(point))
		_top.draw_polyline(points, LINE_COLOR, 2.0, true)

	var font := ThemeDB.fallback_font
	for badge in _badges:
		var center: Vector2 = _top.to_local(badge["at"]) + BADGE_OFFSET
		var text: String = badge["text"]
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		var size := Vector2(maxf(width + 6.0, BADGE_HEIGHT), BADGE_HEIGHT)  # grows with the text
		_top.draw_rect(Rect2(center - size / 2.0, size), BADGE_COLOR)
		_top.draw_string(
			font, center + Vector2(-width / 2.0, FONT_SIZE * 0.35), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color.WHITE)
