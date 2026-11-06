class_name BossObjective
extends KillRoleObjective
## Win when the boss is dead, even if other enemies are still alive.
## The boss is any enemy whose CharacterData.roles contains Role.BOSS.


func _init() -> void:
	role = CharacterData.Role.BOSS
	verb = "Defeat"
	progress_label = "Bosses left"
	description = "Defeat the boss"
