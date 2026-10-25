class_name EnemyIntent
extends RefCounted
## What an enemy has decided to do on its next turn (runtime only, never saved).
## Created by Battle._plan_intent and stored in Character.intent.

var action: EnemyAction
## The hero to hit (MELEE, RANGED, DEBUFF, HEAVY) or the enemy to buff (BUFF). Null for AOE.
var target: Character
## AOE only: the center of the circle, fixed when the intent was planned.
## Heroes can walk out of it before the enemy strikes.
var spot := Vector2.ZERO
## Enemy turns of charging left before the action happens (HEAVY).
var windup_left := 0


func _init(new_action: EnemyAction) -> void:
	action = new_action
	windup_left = new_action.get_windup_turns()


func get_text() -> String:
	return action.get_intent_text(windup_left)
