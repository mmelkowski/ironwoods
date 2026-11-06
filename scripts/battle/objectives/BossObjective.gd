class_name BossObjective
extends BattleObjective
## Win when the boss is dead, even if other enemies are still alive.
## The boss is any enemy whose CharacterData.roles contains Role.BOSS.
##
## Setup: a scene whose root is a BossObjective node, assigned to
## EncounterData.objective_scene; the boss goes in EncounterData.enemies
## (guaranteed enemies), and fill_with_pool can add escorts around it.

## On: every boss must die (two bosses = kill both). Off: the first boss to die ends the fight.
@export var require_all: bool = true

var _bosses: Array[Character] = []
var _boss_names: Array[String] = []
var _bosses_total := 0
## No boss in the battle (data error): behave like KillAllObjective instead of
## ending the battle at once or never.
var _fallback := false


func _init() -> void:
	description = "Defeat the boss"


func _on_start() -> void:
	_bosses.clear()
	_boss_names.clear()
	for enemy in battle.enemies:
		if enemy.data.has_role(CharacterData.Role.BOSS):
			_bosses.append(enemy)
			_boss_names.append(enemy.data.display_name)
	_bosses_total = _bosses.size()

	if _bosses.is_empty():
		_fallback = true
		push_error("BossObjective: no enemy has the BOSS role in this battle, falling back to 'defeat all enemies'. Add Role.BOSS to the roles of the boss CharacterData.")
		description = "Defeat all enemies"
		return
	description = "Defeat " + ", ".join(_boss_names)


func is_complete() -> bool:
	if _fallback:
		return battle.enemies.is_empty()
	var alive := _alive_count()
	return alive == 0 if require_all else alive < _bosses_total


func get_progress_text() -> String:
	if _fallback:
		return "Enemies left: %d" % battle.enemies.size()
	if _bosses_total > 1:
		return "Bosses left: %d" % _alive_count()
	return ""


## A boss is alive while it is in battle.enemies (Battle removes the dead at once,
## before the character node is freed).
func _alive_count() -> int:
	var count := 0
	for boss in _bosses:
		if battle.enemies.has(boss):
			count += 1
	return count
