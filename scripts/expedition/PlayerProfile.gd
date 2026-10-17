class_name PlayerProfile
extends RefCounted
## Everything that persists between expeditions: who is unlocked, what is in the
## stock, what the hub has. Plain data only (ids, numbers, lists), so the save
## system can store it as it is. Heroes and places are referenced by id, never
## by resource.

signal resources_changed

var unlocked_heroes: Array[StringName] = []
var resources: Dictionary = {}           # resource id (&"wood") -> amount (int)
var unlocked_locations: Array[StringName] = []  # hub places (&"forge")
var upgrade_levels: Dictionary = {}      # upgrade id -> level (int)


# --- Heroes ---

func unlock_hero(id: StringName) -> void:
	if not unlocked_heroes.has(id):
		unlocked_heroes.append(id)


func is_hero_unlocked(id: StringName) -> bool:
	return unlocked_heroes.has(id)


# --- Resources ---

func get_resource(id: StringName) -> int:
	return resources.get(id, 0)


func add_resource(id: StringName, amount: int) -> void:
	resources[id] = get_resource(id) + amount
	resources_changed.emit()


## cost: { resource id: amount }
func can_afford(cost: Dictionary) -> bool:
	for id in cost:
		if get_resource(id) < cost[id]:
			return false
	return true


## Pays the cost if the stock allows it. Returns false (and takes nothing) otherwise.
func spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for id in cost:
		resources[id] = get_resource(id) - cost[id]
	resources_changed.emit()
	return true


# --- Hub ---

func unlock_location(id: StringName) -> void:
	if not unlocked_locations.has(id):
		unlocked_locations.append(id)


func is_location_unlocked(id: StringName) -> bool:
	return unlocked_locations.has(id)


func get_upgrade_level(id: StringName) -> int:
	return upgrade_levels.get(id, 0)


func set_upgrade_level(id: StringName, level: int) -> void:
	upgrade_levels[id] = level
