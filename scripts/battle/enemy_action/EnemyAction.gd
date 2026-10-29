@tool
class_name EnemyAction
extends Resource
## One thing an enemy can do on its turn. Authored once as a .tres and listed in
## CharacterData.actions (EnemyAction -> weight), the same way statuses are listed.
##
## Every kind goes through the same pipeline in Battle: the enemy plans it (and shows it to the
## player), then on its next turn it walks within `approach_distance` of the target (or of the
## chosen spot for AOE), deals `damage`, and applies `effects`.
##
## Suggested values:
##   MELEE   damage 5,  approach_distance 32
##   RANGED  damage 4,  approach_distance 160
##   AOE     damage 6,  approach_distance 200, aoe_radius 180   (hits every hero in the circle)
##   BUFF    damage -,  approach_distance 150, effects on TARGET (the ally enemy) or SELF
##   DEBUFF  damage 0,  approach_distance 160, effects on TARGET (the hero), e.g. Bleeding / Stun
##   HEAVY   damage 15, approach_distance 32,  windup_turns 1

enum Kind { MELEE, RANGED, AOE, BUFF, DEBUFF, HEAVY }

@export_group("Identity")
@export var id: StringName
## Shown next to the enemy while the action is planned. Empty = the kind name.
@export var display_name: String = ""

@export_group("Action")
@export var kind: Kind = Kind.MELEE:
	set(value):
		kind = value
		notify_property_list_changed()
## Damage of each hit (BUFF ignores it, DEBUFF can use 0).
@export var damage: int = 5
## The enemy walks until it is at most this far from its target (or from the AOE spot).
## If already close enough it does not move. Melee ~32, ranged more.
@export_range(0.0, 1000.0, 1.0, "or_greater", "suffix:px") var approach_distance: float = 32.0
## AOE: radius of the circle drawn on the ground. Every hero inside gets hit.
@export_range(0.0, 1000.0, 1.0, "or_greater", "suffix:px") var aoe_radius: float = 80.0
## HEAVY: how many enemy turns the enemy only charges before it strikes
## (1 = it does nothing this turn and hits on the next one).
@export_range(0, 10) var windup_turns: int = 1
## BUFF: the enemy may also pick itself as the target.
@export var can_target_self: bool = false

@export_group("Effects")
## Statuses given when the action resolves. Recipient TARGET = who is hit (or the buffed enemy),
## SELF = the enemy itself. The trigger is ignored (ON_KILL effects are skipped).
@export var effects: Array[StatusApplication] = []


func get_damage() -> int:
	return 0 if kind == Kind.BUFF else maxi(damage, 0)


## Turns of charging before the action happens (only HEAVY has any).
func get_windup_turns() -> int:
	return windup_turns if kind == Kind.HEAVY else 0


## BUFF aims at the enemy's own side, everything else at the heroes.
func targets_own_side() -> bool:
	return kind == Kind.BUFF


## Text shown next to the enemy: the name, plus the turns of charging left if any.
func get_intent_text(windup_left: int) -> String:
	var title := display_name if display_name != "" else String(Kind.keys()[kind]).capitalize()
	if windup_left > 0:
		return "%s %d" % [title, windup_left]
	return title


## Color of the text above the enemy, so the player reads the intent at a glance.
func get_color() -> Color:
	match kind:
		Kind.BUFF:
			return Color(0.6, 1.0, 0.6)
		Kind.DEBUFF:
			return Color(0.8, 0.6, 1.0)
		Kind.HEAVY:
			return Color(1.0, 0.6, 0.2)
		Kind.AOE:
			return Color(1.0, 0.4, 0.4)
	return Color.WHITE


func _validate_property(property: Dictionary) -> void:
	var hide := false
	match property.name:
		"damage":
			hide = kind == Kind.BUFF
		"aoe_radius":
			hide = kind != Kind.AOE
		"windup_turns":
			hide = kind != Kind.HEAVY
		"can_target_self":
			hide = kind != Kind.BUFF
	if hide:
		property.usage = PROPERTY_USAGE_NO_EDITOR
