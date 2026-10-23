class_name StatusComponent
extends Node
## Holds the persistent statuses of one character (Bleeding, Stun...) and ticks them.
## Created by code in Character._ready(), so no scene change is needed.
## Instant value effects (armor, heal) and evasion never reach this component:
## Character.apply_status() sends them straight to the HealthComponent.
##
## Turn timing (Battle calls these):
##   start_of_turn()  -> damage over time (Bleeding)
##   ...the owner's side plays (a stunned character can't act)...
##   end_of_turn()    -> TURNS statuses lose their decay

signal changed

## StatusData -> stacks (always > 0)
var stacks: Dictionary = {}

var _health: HealthComponent


func _init(health_component: HealthComponent = null) -> void:
	_health = health_component


func add(status: StatusData, amount: int) -> void:
	if status == null or amount <= 0:
		return
	stacks[status] = stacks.get(status, 0) + amount
	changed.emit()


func get_stacks(status: StatusData) -> int:
	return stacks.get(status, 0)


func has_effect(effect: StatusData.Effect) -> bool:
	for status: StatusData in stacks:
		if status.get_effect() == effect:
			return true
	return false


func is_stunned() -> bool:
	return has_effect(StatusData.Effect.STUN)


## Removes every debuff (Bleeding, Stun...). Returns true if something was removed.
func remove_debuffs() -> bool:
	var removed := false
	for status: StatusData in stacks.keys():
		if status.is_debuff():
			stacks.erase(status)
			removed = true
	if removed:
		changed.emit()
	return removed


## For USES statuses: removes `amount` stacks (e.g. when the effect triggers).
func consume(status: StatusData, amount: int = 1) -> void:
	if not stacks.has(status):
		return
	var left: int = stacks[status] - amount
	if left <= 0:
		stacks.erase(status)
	else:
		stacks[status] = left
	changed.emit()


## Bleeding: `stacks` damage straight to health. May kill the owner (HealthComponent.died).
func start_of_turn() -> void:
	if _health == null:
		return
	for status: StatusData in stacks.keys():
		if _health.is_dead():
			return
		if status.get_effect() == StatusData.Effect.BLEED:
			_health.take_damage(stacks[status], false, status.bypass_armor)


## TURNS statuses lose `decay_per_turn` stacks and disappear at 0.
func end_of_turn() -> void:
	var touched := false
	for status: StatusData in stacks.keys():
		if status.duration_type != StatusData.DurationType.TURNS or status.decay_per_turn <= 0:
			continue
		var left: int = stacks[status] - status.decay_per_turn
		if left <= 0:
			stacks.erase(status)
		else:
			stacks[status] = left
		touched = true
	if touched:
		changed.emit()


## "Bleeding 3  Stunned 1", for the status label above the character.
func get_summary() -> String:
	var parts: Array[String] = []
	for status: StatusData in stacks:
		var label := status.display_name if status.display_name != "" else str(status.id)
		parts.append("%s %d" % [label, stacks[status]])
	return "  ".join(parts)
