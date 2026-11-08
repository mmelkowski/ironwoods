@tool
class_name EventEffect
extends Resource
## Base of everything an event choice can do to the run. Extend it, override what is needed,
## and the new kind appears in the inspector list of EventChoice.effects.
## Like UnlockCondition: the base does nothing and never blocks.


## Short text for the choice button ("Pay: Stone 2"). Empty = nothing to show.
func get_preview() -> String:
	return ""


## Empty when the effect can be applied now, otherwise why not ("Needs Stone 2").
## A choice with a blocked effect is shown greyed out.
func get_blocked_reason(_run: RunState) -> String:
	return ""


## True if get_blocked_reason can ever return something (a cost). A choice made only of
## effects that cannot block is always available; EventData.validate needs one of them.
func can_block() -> bool:
	return false


## Changes the run. Returns a line for the result screen ("Gained: Wood 4"), "" for none.
## `rng` is seeded with the run and the node: the same node always rolls the same numbers,
## so reloading a save cannot reroll an outcome.
func apply(_run: RunState, _rng: RandomNumberGenerator) -> String:
	return ""
