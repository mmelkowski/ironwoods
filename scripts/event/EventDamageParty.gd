@tool
class_name EventDamageParty
extends EventEffect
## Every living hero loses health: a flat `amount` plus a share (`ratio`) of his max health.
## By default nobody can die from it (health stops at 1); turn `can_kill` on for a deadly trap.

@export var amount: int = 0
@export_range(0.0, 1.0, 0.05) var ratio: float = 0.0
@export var can_kill: bool = false


func get_preview() -> String:
	if amount <= 0 and ratio <= 0.0:
		return ""
	if amount > 0 and ratio > 0.0:
		return "Each hero loses %d + %d%% of max health" % [amount, roundi(ratio * 100.0)]
	if amount > 0:
		return "Each hero loses %d health" % amount
	return "Each hero loses %d%% of max health" % roundi(ratio * 100.0)


func apply(run: RunState, _rng: RandomNumberGenerator) -> String:
	var lines: PackedStringArray = []
	for hero in GameState.get_run_team():
		var before := run.get_health(hero.id)
		if before <= 0:
			continue
		var floor_health := 0 if can_kill else 1
		var after := maxi(floor_health, before - amount - ceili(hero.max_health * ratio))
		if after < before:
			run.set_health(hero.id, after)
			lines.append("%s loses %d health" % [hero.display_name, before - after])
	return "\n".join(lines)
