class_name BattleObjective
extends Node
## Base class of every battle objective (kill everyone, kill a boss, destroy an
## object, survive waves, rescue a hostage...).
##
## How it is used: the Battle calls start() once before the first turn, then asks
## is_complete() / is_failed() after every action (a card, an enemy attack).
## Checking at those safe moments, instead of reacting to events in the middle of
## an attack, keeps the end of the battle predictable.
##
## To make a new objective: extend this class and override what you need.
## Being a Node, an objective can have @export references to things in the battle
## scene (a boss, a chest, a hostage...). Assign it to Battle.objective.

## Shown in the HUD ("Defeat all enemies").
@export var description: String = ""

var battle: Battle


## False until the Battle has called start(). Before that, `battle` is null,
## so anything reading the battle (the HUD, for instance) must check this first.
func is_started() -> bool:
	return battle != null


## Called once by the Battle after the characters are spawned.
func start(target_battle: Battle) -> void:
	battle = target_battle
	_on_start()


## Override to connect to battle signals (turn_started...), find targets, spawn waves...
func _on_start() -> void:
	pass


## Victory condition.
func is_complete() -> bool:
	return false


## Optional defeat condition on top of "all allies are dead" (hostage killed, timer out...).
func is_failed() -> bool:
	return false


## Optional progress for the HUD, e.g. "Enemies left: 3". Empty = nothing shown.
func get_progress_text() -> String:
	return ""
