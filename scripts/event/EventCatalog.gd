@tool
class_name EventCatalog
extends Resource
## Every event that can be drawn at random. One file: `data/event_catalog.tres` (built by
## tools/make_events.gd or filled by hand). Events used only as the fixed `event` of a node
## do not have to be listed.

const PATH := "res://data/event_catalog.tres"

@export var events: Array[EventData] = []

@export_tool_button("Validate catalog") var validate_button = _print_validation


func get_event(event_id: StringName) -> EventData:
	for event in events:
		if event != null and event.id == event_id:
			return event
	return null


## The events that can be drawn for an expedition with these tags (weight 0 = fixed only).
func get_pool(tags: Array[StringName]) -> Array[EventData]:
	var pool: Array[EventData] = []
	for event in events:
		if event != null and event.weight > 0.0 and event.fits(tags):
			pool.append(event)
	return pool


## The problems found (empty = valid).
func validate() -> Array[String]:
	var problems: Array[String] = []
	var seen := {}
	for event in events:
		if event == null:
			problems.append("an entry of `events` is empty.")
			continue
		if event.id != &"":
			if seen.has(event.id):
				problems.append("the id '%s' is used by several events." % event.id)
			seen[event.id] = true
		for problem in event.validate():
			problems.append("event '%s' %s" % [event.id, problem])
	return problems


func _print_validation() -> void:
	var problems := validate()
	if problems.is_empty():
		print("Event catalog: valid (%d events)." % events.size())
		return
	for problem in problems:
		push_warning("Event catalog: %s" % problem)
