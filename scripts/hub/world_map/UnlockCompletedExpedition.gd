class_name UnlockCompletedExpedition
extends UnlockCondition
## Met once the player has finished the given expedition at least once.

@export var expedition_id: StringName


func is_met(profile: PlayerProfile) -> bool:
	return profile.is_expedition_completed(expedition_id)


func describe() -> String:
	var expedition := GameState.expeditions.get_expedition(expedition_id)
	var title := expedition.display_name if expedition != null else String(expedition_id)
	return "Complete \"%s\"" % title
