@tool
class_name CardData
extends Resource
## Static definition of a card. Never modify this at runtime: it is shared by
## every copy of the card. Runtime changes (crit buff, bonus damage...) go on a
## CardInstance instead.
##
## @tool lets the inspector hide fields that don't apply to the current
## card type / target type.

enum Type { ATTACK, SUPPORT, MANA }
enum TargetType { SINGLE, MULTIPLE, CHAINED, AOE }
enum TargetTeam { ENEMY, ALLY, SELF }
enum Knockback { NONE, STANDARD, FORCEFUL }

@export_group("Identity")
@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var art: Texture2D

@export_group("Type & Mana")
@export var card_type: Type = Type.ATTACK:
	set(value):
		card_type = value
		notify_property_list_changed()
## Mana gained when played. Attack cards: 1, support cards: 2 or more.
@export var mana_generation: int = 1
## Mana spent when played. Only used by MANA cards.
@export var mana_cost: int = 1

@export_group("Damage")
@export var damage: int = 0
@export var knockback: Knockback = Knockback.NONE
## Base critical state. Other cards can turn it on through the CardInstance.
@export var critical: bool = false

@export_group("Rules")
## Quick: the action point is refunded if this card kills at least one target.
@export var quick: bool = false

@export_group("Targeting")
@export var target_team: TargetTeam = TargetTeam.ENEMY
@export var target_type: TargetType = TargetType.SINGLE:
	set(value):
		target_type = value
		notify_property_list_changed()
## MULTIPLE / CHAINED: how many targets the player picks.
@export var max_targets: int = 2
## MULTIPLE: only targets within this radius of the caster can be picked (0 = no limit).
@export_range(0.0, 1000.0, 1.0, "or_greater", "suffix:px") var select_radius: float = 160.0
## CHAINED: each next target must be within this radius of the previous one.
@export_range(0.0, 1000.0, 1.0, "or_greater", "suffix:px") var chain_radius: float = 64.0
## AOE: radius around the chosen target.
@export_range(0.0, 1000.0, 1.0, "or_greater", "suffix:px") var aoe_radius: float = 64.0

@export_group("Movement")
## Max distance from the target at which the card can be played.
## The caster moves to the closest position that satisfies it (melee ~32, ranged more).
## If already in range, the caster doesn't move.
@export_range(0.0, 1000.0, 1.0, "or_greater", "suffix:px") var approach_distance: float = 32.0
@export var use_approach_angle: bool = false:
	set(value):
		use_approach_angle = value
		notify_property_list_changed()
## Forces the caster to a specific spot around the target, relative to the
## direction the caster is coming from:
## 0 = same side as the caster (straight approach), 180 = opposite side (backstab),
## +/-90 = the flanks. The caster is placed exactly approach_distance away.
## (Godot 2D: positive angles go clockwise on screen.)
@export_range(-180.0, 180.0, 1.0, "degrees") var approach_angle: float = 0.0

@export_group("Effects")
## Statuses given on play or on kill. See StatusApplication.
@export var effects: Array[StatusApplication] = []


## Where the caster must stand to play this card on a target.
func get_approach_position(caster_pos: Vector2, target_pos: Vector2) -> Vector2:
	if use_approach_angle:
		# Fixed spot around the target, measured from the side the caster comes from
		# (e.g. 180 = behind the target relative to the caster, for a backstab).
		var from_dir := target_pos.direction_to(caster_pos)
		if from_dir == Vector2.ZERO:
			from_dir = Vector2.LEFT
		return target_pos + from_dir.rotated(deg_to_rad(approach_angle)) * approach_distance

	return closest_in_range(caster_pos, target_pos, approach_distance)


## Closest position to `from` that is within `max_distance` of `to`.
## Returns `from` unchanged if already in range. Also used for enemy attacks.
static func closest_in_range(from: Vector2, to: Vector2, max_distance: float) -> Vector2:
	if from.distance_to(to) <= max_distance:
		return from
	return to + to.direction_to(from) * max_distance


func _validate_property(property: Dictionary) -> void:
	var hide := false
	match property.name:
		"mana_generation":
			hide = card_type == Type.MANA
		"mana_cost":
			hide = card_type != Type.MANA
		"max_targets":
			hide = target_type == TargetType.SINGLE or target_type == TargetType.AOE
		"select_radius":
			hide = target_type != TargetType.MULTIPLE
		"chain_radius":
			hide = target_type != TargetType.CHAINED
		"aoe_radius":
			hide = target_type != TargetType.AOE
		"approach_angle":
			hide = not use_approach_angle
	if hide:
		property.usage = PROPERTY_USAGE_NO_EDITOR
