class_name UnlockBuildingLevel
extends UnlockCondition
## Met once a hub building is built (level 1) or upgraded to the given level.

@export var building_id: StringName
@export_range(1, 20) var level: int = 1


func is_met(profile: PlayerProfile) -> bool:
	return profile.get_upgrade_level(building_id) >= level


func describe() -> String:
	var building := GameState.buildings.get_building(building_id)
	var title := building.display_name if building != null else String(building_id)
	if level <= 1:
		return "Build the %s" % title
	return "Upgrade the %s to level %d" % [title, level]
