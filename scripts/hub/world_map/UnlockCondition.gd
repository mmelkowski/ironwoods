class_name UnlockCondition
extends Resource
## One requirement for a location of the world map to be available.
## This is the base: it is always met. Subclasses (UnlockCompletedExpedition,
## UnlockBuildingLevel...) override is_met() and describe().
##
## To add a new kind of requirement (a hero unlocked, an amount of a resource...), make a new
## script that extends UnlockCondition. It then appears in the "unlock_conditions" list of
## ExpeditionData ("Add element" > "New ...").

## True when the player's profile satisfies the requirement.
func is_met(_profile: PlayerProfile) -> bool:
	return true


## Short text telling the player what to do ("Complete The Old Road").
func describe() -> String:
	return ""
