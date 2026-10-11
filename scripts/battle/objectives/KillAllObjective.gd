class_name KillAllObjective
extends BattleObjective
## Win when no enemy is left. This is the default objective.


func _init() -> void:
	description = "Defeat all enemies"


func is_complete() -> bool:
	return battle.enemies.is_empty()


func get_progress_text() -> String:
	return "Enemies left: %d" % battle.enemies.size()
