class_name StatusComponent
extends Node
## Holds the persistent statuses of one character (Bleeding, Stun...) and ticks them.
## Created by code in Character._ready(), so no scene change is needed.
## Instant value effects (armor, heal) never reach this component:
## Character.apply_status() sends them straight to the HealthComponent.
## Everything else is stored here, evasion included.
##
## Turn timing (Battle calls these):
##   start_of_turn()  -> damage over time (Bleeding, Poison)
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


func is_asleep() -> bool:
	return has_effect(StatusData.Effect.SLEEP)


## Cannot act: stunned or asleep. Battle uses this to block cards and skip enemy turns.
func is_incapacitated() -> bool:
	return is_stunned() or is_asleep()


## A hit woke the owner: removes every SLEEP status. Returns true if something was removed.
func wake_up() -> bool:
	var woke := false
	for status: StatusData in stacks.keys():
		if status.get_effect() == StatusData.Effect.SLEEP:
			stacks.erase(status)
			woke = true
	if woke:
		changed.emit()
	return woke


## Evasion: true if the incoming hit is dodged. USES evasion loses one stack per dodge,
## TURNS evasion dodges every hit while it lasts.
func try_dodge() -> bool:
	for status: StatusData in stacks.keys():
		if status.get_effect() == StatusData.Effect.EVASION:
			if status.duration_type == StatusData.DurationType.USES:
				consume(status, 1)
			return true
	return false


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


## Removes every stack of a status and returns how many there were (0 if it was not there).
## For stacks that a card spends all at once (arcane charges).
func consume_all(status: StatusData) -> int:
	var amount := get_stacks(status)
	if amount > 0:
		consume(status, amount)
	return amount


## Damage over time, never dodged. BLEED: tick_damage x stacks. POISON: tick_damage, whatever the
## stacks (see StatusData.get_tick_damage). Armor is ignored unless the status says otherwise.
## May kill the owner (HealthComponent.died).
func start_of_turn() -> void:
	if _health == null:
		return
	for status: StatusData in stacks.keys():
		if _health.is_dead():
			return
		if status.is_tick_effect():
			_health.take_damage(status.get_tick_damage(get_stacks(status)), false, status.bypass_armor)


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
