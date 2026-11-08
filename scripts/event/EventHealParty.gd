@tool
class_name EventHealParty
extends EventEffect
## Every living hero recovers health: a flat `amount` plus a share (`ratio`) of his max health.
## A downed hero (0 health) stays down unless `revive` is on (a camp revives, a short rest does not).

@export var amount: int = 0
@export_range(0.0, 1.0, 0.05) var ratio: float = 0.0
@export var revive: bool = false


func get_preview() -> String:
	if amount <= 0 and ratio <= 0.0:
		return ""
	if amount > 0 and ratio > 0.0:
		return "Each hero recovers %d + %d%% of max health" % [amount, roundi(ratio * 100.0)]
	if amount > 0:
		return "Each hero recovers %d health" % amount
	return "Each hero recovers %d%% of max health" % roundi(ratio * 100.0)


func apply(run: RunState, _rng: RandomNumberGenerator) -> String:
	var lines: PackedStringArray = []
	for hero in GameState.get_run_team():
		var before := run.get_health(hero.id)
		if before <= 0 and not revive:
			continue
		var after := mini(hero.max_health, before + amount + ceili(hero.max_health * ratio))
		if after > before:
			run.set_health(hero.id, after)
			lines.append("%s recovers %d health" % [hero.display_name, after - before])
	if lines.is_empty():
		return "Nobody needed healing."
	return "\n".join(lines)
