class_name BuildingData
extends Resource
## A building of the hub: the gate, the carpentry workshop, the tavern, the forge...
## Create one .tres per building and list them in the BuildingCatalog.
##
## `id` must be the `location_id` of the HubLocation that shows this building in
## the hub scene. A building is invisible in the hub until it is built.

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
## Already built (level 1) in a new game, like the gate and the carpentry workshop.
@export var built_at_start: bool = false
## Other buildings needed before this one can be built: { building id: minimum level }.
## Buildings whose requirements are not met stay hidden in the carpentry workshop.
@export var requires: Dictionary[StringName, int] = {}
## levels[0] = building it (level 1), levels[1] = the upgrade to level 2, and so on.
@export var levels: Array[BuildingLevel] = []


func get_max_level() -> int:
	return levels.size()


## The data of a level, counting from 1. Null if the level doesn't exist.
func get_level_data(level: int) -> BuildingLevel:
	if level < 1 or level > levels.size():
		return null
	return levels[level - 1]
