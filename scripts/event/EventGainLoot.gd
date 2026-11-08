@tool
class_name EventGainLoot
extends EventEffect
## The party finds resources. They go into the run's loot (kept even if the expedition fails).

@export var loot: Dictionary[StringName, int] = {}


func get_preview() -> String:
	if loot.is_empty():
		return ""
	return "Gain: %s" % ResourceBar.describe(loot)


func apply(run: RunState, _rng: RandomNumberGenerator) -> String:
	if loot.is_empty():
		return ""
	for id in loot:
		run.add_loot(id, loot[id])
	return "Gained: %s" % ResourceBar.describe(loot)
