class_name KillRoleObjective
extends BattleObjective
## Win when the enemies that have a given CharacterData.Role are dead, even if other enemies
## are still alive. Base of BossObjective (Role.BOSS) and DestroyObjectObjective (Role.OBJECT);
## usable on its own by setting `role` in the inspector.
##
## Setup: a scene whose root is the objective node, assigned to EncounterData.objective_scene;
## the targets go in EncounterData.enemies (guaranteed enemies).

@export var role: CharacterData.Role = CharacterData.Role.BOSS
## "Defeat" or "Destroy": the HUD shows "<verb> <names>".
@export var verb: String = "Defeat"
## HUD text when several targets exist: "<progress_label>: N".
@export var progress_label: String = "Targets left"
## On: every target must die. Off: the first one to die ends the fight.
@export var require_all: bool = true

var _targets: Array[Character] = []
var _target_names: Array[String] = []
var _targets_total := 0
## No enemy has the role (data error): behave like KillAllObjective instead of
## ending the battle at once or never.
var _fallback := false


func _init() -> void:
	description = "Defeat the target"


func _on_start() -> void:
	_targets.clear()
	_target_names.clear()
	for enemy in battle.enemies:
		if enemy.data.has_role(role):
			_targets.append(enemy)
			_target_names.append(enemy.data.display_name)
			_on_target_found(enemy)
	_targets_total = _targets.size()

	if _targets.is_empty():
		_fallback = true
		push_error("%s: no enemy has the %s role in this battle, falling back to 'defeat all enemies'. Add it to the roles of the CharacterData." % [get_class(), CharacterData.Role.keys()[role]])
		description = "Defeat all enemies"
		return
	description = "%s %s" % [verb, ", ".join(_target_names)]


## Hook for subclasses: called once per target found at the start.
func _on_target_found(_target: Character) -> void:
	pass


func is_complete() -> bool:
	if _fallback:
		return battle.enemies.is_empty()
	var alive := _alive_count()
	return alive == 0 if require_all else alive < _targets_total


func get_progress_text() -> String:
	if _fallback:
		return "Enemies left: %d" % battle.enemies.size()
	if _targets_total > 1:
		return "%s: %d" % [progress_label, _alive_count()]
	return ""


## A target is alive while it is in battle.enemies (Battle removes the dead at once,
## before the character node is freed).
func _alive_count() -> int:
	var count := 0
	for target in _targets:
		if battle.enemies.has(target):
			count += 1
	return count
