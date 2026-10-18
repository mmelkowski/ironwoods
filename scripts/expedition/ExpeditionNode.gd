@tool
class_name ExpeditionNode
extends Resource
## One stop of an expedition: a battle, a camp, an event... The nodes of an
## expedition form a graph (see ExpeditionData). Nodes point to the ones that
## come next by id, never by reference, so a run can be saved as plain ids.

enum Type {
	START,   ## the departure: nothing happens, the player picks the first road
	BATTLE,
	BOSS,    ## a battle, shown differently on the map
	CAMP,    ## rest: the heroes recover health
	EVENT,   ## a story event (not implemented yet)
	END,     ## reaching it completes the expedition
}

@export var id: StringName
@export var type: Type = Type.BATTLE:
	set(value):
		type = value
		notify_property_list_changed()
@export var title: String = ""
@export_multiline var description: String = ""
## The nodes the player can go to after this one (their ids). Several entries = a fork.
@export var next_nodes: Array[StringName] = []
## Battle and boss nodes only.
@export var encounter: EncounterData
## Resources the party gathers when it finishes this node (a won battle, an event...).
## They go into the run's loot and are kept even if the expedition fails.
@export var loot: Dictionary[StringName, int] = {}
## Hint for the map layout: vertical position of the node inside its column.
## -1 = top, 0 = middle, 1 = bottom. Nodes of the same column should use different lanes.
@export_range(-1.0, 1.0, 0.05) var lane: float = 0.0


func has_encounter() -> bool:
	return type == Type.BATTLE or type == Type.BOSS


func _validate_property(property: Dictionary) -> void:
	if property.name == "encounter" and not has_encounter():
		property.usage = PROPERTY_USAGE_NO_EDITOR
