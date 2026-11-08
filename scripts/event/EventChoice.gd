@tool
class_name EventChoice
extends Resource
## One button of an event: a label, what it does (effects, applied in order) and the text
## shown afterwards. An empty `effects` list is a plain "walk away" or "listen" choice.

@export var label: String = ""
## Told to the player after the choice, above the list of changes ("Gained: Wood 4").
@export_multiline var result_text: String = ""
@export var effects: Array[EventEffect] = []


## What the choice does, for under its label: "Pay: Stone 2, Gain: Wood 4".
func get_preview() -> String:
	var parts: PackedStringArray = []
	for effect in effects:
		if effect == null:
			continue
		var text := effect.get_preview()
		if text != "":
			parts.append(text)
	return ", ".join(parts)


## Empty when the choice can be picked now, otherwise the reason ("Needs Stone 2").
func get_blocked_reason(run: RunState) -> String:
	for effect in effects:
		if effect == null:
			continue
		var reason := effect.get_blocked_reason(run)
		if reason != "":
			return reason
	return ""


## True when no effect can ever block it (no cost): the player can always pick it.
func is_always_available() -> bool:
	for effect in effects:
		if effect != null and effect.can_block():
			return false
	return true


## Applies every effect. Returns the lines for the result screen.
func apply(run: RunState, rng: RandomNumberGenerator) -> PackedStringArray:
	var lines: PackedStringArray = []
	if get_blocked_reason(run) != "":
		push_warning("EventChoice '%s' applied while blocked: nothing done." % label)
		return lines
	for effect in effects:
		if effect == null:
			continue
		var line := effect.apply(run, rng)
		if line != "":
			lines.append(line)
	return lines
