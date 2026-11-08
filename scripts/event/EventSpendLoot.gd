@tool
class_name EventSpendLoot
extends EventEffect
## The party pays with the loot it carries (never with the hub stock). If it cannot pay,
## the choice is greyed out with "Needs ...".

@export var cost: Dictionary[StringName, int] = {}


func get_preview() -> String:
	if cost.is_empty():
		return ""
	return "Pay: %s" % ResourceBar.describe(cost)


func can_block() -> bool:
	return not cost.is_empty()


func get_blocked_reason(run: RunState) -> String:
	if run.can_afford(cost):
		return ""
	return "Needs %s" % ResourceBar.describe(cost)


func apply(run: RunState, _rng: RandomNumberGenerator) -> String:
	if cost.is_empty():
		return ""
	if not run.spend_loot(cost):
		push_warning("EventSpendLoot: the party cannot pay %s." % ResourceBar.describe(cost))
		return ""
	return "Paid: %s" % ResourceBar.describe(cost)
