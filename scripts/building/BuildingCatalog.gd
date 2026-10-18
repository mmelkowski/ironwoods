class_name BuildingCatalog
extends Resource
## The list of every building of the hub, and the lookup from a building id.
## One .tres (data/building_catalog.tres) that references the building .tres files.

@export var buildings: Array[BuildingData] = []


func get_building(id: StringName) -> BuildingData:
	for building in buildings:
		if building.id == id:
			return building
	return null


## Warns about problems in the data: empty or duplicate ids, buildings without
## levels, requirements on buildings that don't exist. Called when the game starts.
func validate() -> void:
	var seen := {}
	for building in buildings:
		if building.id == &"":
			push_warning("BuildingCatalog: '%s' has no id." % building.display_name)
		elif seen.has(building.id):
			push_warning("BuildingCatalog: the id '%s' is used by several buildings." % building.id)
		seen[building.id] = true
		if building.levels.is_empty():
			push_warning("BuildingCatalog: '%s' has no levels, it can never be built." % building.id)
	for building in buildings:
		for required_id in building.requires:
			if not seen.has(required_id):
				push_warning("BuildingCatalog: '%s' requires '%s', which doesn't exist." % [building.id, required_id])
