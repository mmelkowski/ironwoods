@tool
extends EditorScript
## One-shot helper that creates the first buildings and the building catalog.
## Open this script in the script editor and use File > Run (Ctrl+Shift+X).
## Running it again overwrites these buildings (and the catalog).
##
## gate       built at start
## carpentry  built at start; level 2 unlocks the forge
## tavern     needs the carpentry
## forge      needs the carpentry at level 2

const BUILDINGS_DIR := "res://data/buildings"
const CATALOG_PATH := "res://data/building_catalog.tres"


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(BUILDINGS_DIR)
	var catalog := BuildingCatalog.new()

	catalog.buildings.append(_save(_building(
		&"gate", "Main gate", "Where the expeditions start.", true, {},
		[_level({}, "Send a team on expeditions.")])))

	catalog.buildings.append(_save(_building(
		&"carpentry", "Carpentry workshop", "Builds and upgrades the buildings of the camp.", true, {},
		[
			_level({}, "Build and upgrade buildings."),
			_level({&"wood": 20, &"stone": 10}, "Allows building the forge."),
		])))

	catalog.buildings.append(_save(_building(
		&"tavern", "Tavern", "A place to prepare an expedition.", false, {&"carpentry": 1},
		[
			_level({&"wood": 10, &"stone": 5}, "Choose a buff before an expedition."),
			_level({&"wood": 25, &"stone": 15, &"iron": 5}, "More buffs to choose from."),
		])))

	catalog.buildings.append(_save(_building(
		&"forge", "Forge", "Crafts equipment.", false, {&"carpentry": 2},
		[_level({&"wood": 15, &"stone": 10, &"iron": 5}, "Craft items to take on expeditions.")])))

	if ResourceSaver.save(catalog, CATALOG_PATH) != OK:
		push_error("make_test_buildings: couldn't save %s" % CATALOG_PATH)
		return
	EditorInterface.get_resource_filesystem().scan()
	print("Buildings saved. Catalog: %s" % CATALOG_PATH)


func _level(cost: Dictionary, description: String) -> BuildingLevel:
	var level := BuildingLevel.new()
	for resource_id in cost:
		level.cost[resource_id] = cost[resource_id]
	level.description = description
	return level


func _building(id: StringName, display_name: String, description: String, built_at_start: bool,
		requires: Dictionary, levels: Array) -> BuildingData:
	var building := BuildingData.new()
	building.id = id
	building.display_name = display_name
	building.description = description
	building.built_at_start = built_at_start
	for building_id in requires:
		building.requires[building_id] = requires[building_id]
	for level in levels:
		building.levels.append(level)
	return building


## Saves a building as its own .tres and returns the saved resource (the one the catalog references).
func _save(building: BuildingData) -> BuildingData:
	var path := "%s/%s.tres" % [BUILDINGS_DIR, building.id]
	if ResourceSaver.save(building, path) != OK:
		push_error("make_test_buildings: couldn't save %s" % path)
		return building
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as BuildingData
