class_name ExpeditionNodeButton
extends Button
## One node of the expedition map. Created by ExpeditionMap, no scene needed.
## Placeholder look (a text button): restyle it with a theme, or turn it into a scene later.

enum State {
	LOCKED,     ## too far ahead: visible but not reachable yet
	REACHABLE,  ## the player can go there now
	CURRENT,    ## where the party is
	VISITED,    ## already passed
}

const SIZE := Vector2(76.0, 44.0)
const TYPE_NAMES := {
	ExpeditionNode.Type.START: "Start",
	ExpeditionNode.Type.BATTLE: "Battle",
	ExpeditionNode.Type.BOSS: "Boss",
	ExpeditionNode.Type.CAMP: "Camp",
	ExpeditionNode.Type.EVENT: "Event",
	ExpeditionNode.Type.END: "End",
}
const STATE_TINT := {
	State.LOCKED: Color(0.55, 0.55, 0.55),
	State.REACHABLE: Color(1.25, 1.15, 0.6),
	State.CURRENT: Color(0.7, 1.2, 0.7),
	State.VISITED: Color(0.4, 0.4, 0.4),
}

var node_data: ExpeditionNode


func setup(node: ExpeditionNode) -> void:
	node_data = node
	text = TYPE_NAMES[node.type]
	tooltip_text = node.title if node.description == "" else "%s\n%s" % [node.title, node.description]
	custom_minimum_size = SIZE
	size = SIZE
	focus_mode = Control.FOCUS_NONE


## Only reachable nodes can be clicked.
func set_state(state: State) -> void:
	disabled = state != State.REACHABLE
	modulate = STATE_TINT[state]
