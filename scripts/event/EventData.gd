@tool
class_name EventData
extends Resource
## A story event of an EVENT node: a text and a few choices. Author one `.tres` per event and
## list it in the EventCatalog (`data/event_catalog.tres`), or put it directly in the
## `event` field of an ExpeditionNode for a hand-made one.

@export var id: StringName
@export var title: String = ""
@export_multiline var text: String = ""
## Optional picture shown above the text.
@export var art: Texture2D

@export_group("Selection")
## Where it can happen: it fits an expedition that shares at least one of these tags with its
## `enemy_tags` ("forest", "catacomb"...). Empty = fits every expedition.
@export var tags: Array[StringName] = []
## Chance relative to the other eligible events. 0 = never drawn (fixed events only).
@export_range(0.0, 100.0, 0.1) var weight: float = 1.0
## On: once seen in a run, it cannot be drawn again in that run.
@export var unique_per_run: bool = false

@export_group("Choices")
@export var choices: Array[EventChoice] = []


## Does it fit an expedition with these tags?
func fits(expedition_tags: Array[StringName]) -> bool:
	if tags.is_empty():
		return true
	for tag in tags:
		if expedition_tags.has(tag):
			return true
	return false


## The problems found (empty = valid).
func validate() -> Array[String]:
	var problems: Array[String] = []
	if id == &"":
		problems.append("has no id.")
	if title == "":
		problems.append("has no title.")
	if choices.is_empty():
		problems.append("has no choice.")
		return problems
	var always_available := false
	for i in choices.size():
		var choice := choices[i]
		if choice == null:
			problems.append("choice %d is empty." % i)
			continue
		if choice.label == "":
			problems.append("choice %d has no label." % i)
		for effect in choice.effects:
			if effect == null:
				problems.append("choice %d has an empty effect." % i)
		if choice.is_always_available():
			always_available = true
	if not always_available:
		problems.append("every choice has a cost: add one the player can always pick (\"Leave\").")
	return problems
