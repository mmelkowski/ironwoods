class_name IntentOverlay
extends Node2D
## Draws the ground circle of every planned AOE enemy action.
## Created by code in Battle._ready() (nothing to build in the editor), placed just
## before %Allies so the circles are drawn under the characters.

const FILL_COLOR := Color(0.9, 0.1, 0.1, 0.18)
const EDGE_COLOR := Color(0.95, 0.25, 0.25, 0.85)
const EDGE_WIDTH := 2.0

var battle: Battle


func _ready() -> void:
	if battle != null:
		battle.intents_changed.connect(queue_redraw)
	queue_redraw()


func _draw() -> void:
	if battle == null:
		return
	for enemy in battle.enemies:
		var intent := enemy.intent
		if intent == null or intent.action.kind != EnemyAction.Kind.AOE:
			continue
		var center := to_local(intent.spot)
		var radius := intent.action.aoe_radius
		draw_circle(center, radius, FILL_COLOR)
		draw_arc(center, radius, 0.0, TAU, 64, EDGE_COLOR, EDGE_WIDTH)
