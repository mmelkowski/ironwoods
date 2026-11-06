@tool
class_name SpawnZone
extends Node2D
## An area where characters of one side can start a battle, for one spawn pattern.
## Place several under %AllySpawns / %EnemySpawns: Battle uses the zones whose `pattern`
## matches the encounter (STANDARD zones when the pattern has none on that side).
## Drawn in the editor only (translucent shape), invisible in the game.

@export var pattern: EncounterData.SpawnPattern = EncounterData.SpawnPattern.STANDARD:
	set(value):
		pattern = value
		queue_redraw()
## Width and height of the area, centred on the node.
@export var size := Vector2(200.0, 200.0):
	set(value):
		size = value
		queue_redraw()
## Ellipse instead of rectangle.
@export var elliptic := false:
	set(value):
		elliptic = value
		queue_redraw()
## How many characters this zone is meant to hold. With several zones on a side, the group is
## shared in proportion to the capacities; the sum is also the maximum number of generated enemies.
@export_range(1, 8) var capacity: int = 3
## Enemy side only. On: the zone is used only by characters that don't act (a totem, see
## CharacterData.acts), never by normal enemies, and it doesn't count in the number of generated
## enemies. Without such a zone, those characters use the normal enemy zones.
@export var objects_only := false:
	set(value):
		objects_only = value
		queue_redraw()

const COLORS := {
	EncounterData.SpawnPattern.STANDARD: Color(0.3, 0.6, 1.0),
	EncounterData.SpawnPattern.AMBUSH: Color(0.3, 0.9, 0.4),
	EncounterData.SpawnPattern.AMBUSHED: Color(1.0, 0.35, 0.3),
}
const OBJECT_COLOR := Color(1.0, 0.85, 0.2)
const ELLIPSE_POINTS := 32


## A uniformly random global position inside the zone (follows its position, rotation and scale).
func random_point(rng: RandomNumberGenerator) -> Vector2:
	var local: Vector2
	if elliptic:
		var angle := rng.randf() * TAU
		var radius := sqrt(rng.randf())  # sqrt = uniform over the area, not clustered in the centre
		local = Vector2(cos(angle), sin(angle)) * radius * size * 0.5
	else:
		local = Vector2(rng.randf_range(-0.5, 0.5) * size.x, rng.randf_range(-0.5, 0.5) * size.y)
	return to_global(local)


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var color: Color = COLORS.get(pattern, Color.WHITE)
	if objects_only:
		color = OBJECT_COLOR
	var outline := PackedVector2Array()
	if elliptic:
		for i in ELLIPSE_POINTS + 1:
			var angle := TAU * i / ELLIPSE_POINTS
			outline.append(Vector2(cos(angle), sin(angle)) * size * 0.5)
	else:
		var half := size * 0.5
		outline = PackedVector2Array([
			Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
			Vector2(half.x, half.y), Vector2(-half.x, half.y), Vector2(-half.x, -half.y)])
	var fill := outline.duplicate()
	fill.remove_at(fill.size() - 1)  # polygon must not repeat its first point
	draw_colored_polygon(fill, Color(color, 0.25))
	draw_polyline(outline, Color(color, 0.9), 2.0)
