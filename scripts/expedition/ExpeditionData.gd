@tool
class_name ExpeditionData
extends Resource
## An expedition: a destination and the graph (a DAG) of nodes leading to its end.
## There is one START node, and one or more END nodes (several ends allow secret objectives).
## Author it in the inspector: add nodes to `nodes`, link them with `next_nodes`, then
## press the "Validate graph" button to check it.

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
## What the player is trying to achieve (shown in the gate menu).
@export_multiline var goal: String = ""
## Extra resources given when the expedition is completed (an END node reached).
## Failing or abandoning keeps the loot gathered on the way but not this bonus.
@export var completion_bonus: Dictionary[StringName, int] = {}
@export var nodes: Array[ExpeditionNode] = []

@export_tool_button("Validate graph") var validate_button = _print_validation

var _by_id: Dictionary = {}  # id -> ExpeditionNode, built when first needed


# ---------------------------------------------------------------------------
# Lookups
# ---------------------------------------------------------------------------

func get_node_by_id(node_id: StringName) -> ExpeditionNode:
	if _by_id.size() != nodes.size():
		_by_id.clear()
		for node in nodes:
			if node != null:
				_by_id[node.id] = node
	return _by_id.get(node_id)


## The single START node (null if there is none).
func get_start() -> ExpeditionNode:
	for node in nodes:
		if node.type == ExpeditionNode.Type.START:
			return node
	return null


func get_end_nodes() -> Array[ExpeditionNode]:
	var result: Array[ExpeditionNode] = []
	for node in nodes:
		if node.type == ExpeditionNode.Type.END:
			result.append(node)
	return result


## The nodes the player can choose from after `node_id`.
func get_next_nodes(node_id: StringName) -> Array[ExpeditionNode]:
	var result: Array[ExpeditionNode] = []
	var node := get_node_by_id(node_id)
	if node == null:
		return result
	for next_id in node.next_nodes:
		var next := get_node_by_id(next_id)
		if next != null:
			result.append(next)
	return result


## Column of each node for the map layout: its distance from the start along the
## longest path. { node id: column }. Only meaningful on a valid graph.
func get_depths() -> Dictionary:
	var depths := {}
	for node_id in _topological_order():
		var depth: int = depths.get(node_id, 0)
		depths[node_id] = depth
		for next_id in get_node_by_id(node_id).next_nodes:
			depths[next_id] = maxi(depths.get(next_id, 0), depth + 1)
	return depths


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

## Returns the list of problems found (empty = the expedition is valid).
func validate() -> Array[String]:
	var problems: Array[String] = []
	_by_id.clear()

	# Ids
	var seen := {}
	for node in nodes:
		if node == null:
			problems.append("an entry of `nodes` is empty.")
			return problems
		if node.id == &"":
			problems.append("a %s node has no id." % ExpeditionNode.Type.keys()[node.type])
		elif seen.has(node.id):
			problems.append("the id '%s' is used by several nodes." % node.id)
		seen[node.id] = true
	if not problems.is_empty():
		return problems  # the rest of the checks rely on unique ids

	# Start and ends
	var start_count := 0
	for node in nodes:
		if node.type == ExpeditionNode.Type.START:
			start_count += 1
	if start_count != 1:
		problems.append("there must be exactly one START node (found %d)." % start_count)
	if get_end_nodes().is_empty():
		problems.append("there must be at least one END node.")

	# Links and node contents
	var has_incoming := {}
	for node in nodes:
		for next_id in node.next_nodes:
			has_incoming[next_id] = true
	for node in nodes:
		for next_id in node.next_nodes:
			if not seen.has(next_id):
				problems.append("'%s' leads to '%s', which doesn't exist." % [node.id, next_id])
			elif next_id == node.id:
				problems.append("'%s' leads to itself." % node.id)
		if node.next_nodes.size() != _count_unique(node.next_nodes):
			problems.append("'%s' lists the same next node twice." % node.id)

		match node.type:
			ExpeditionNode.Type.END:
				if not node.next_nodes.is_empty():
					problems.append("the END node '%s' must not lead anywhere." % node.id)
			ExpeditionNode.Type.START:
				if has_incoming.has(node.id):
					problems.append("nothing may lead to the START node.")
				if node.next_nodes.is_empty():
					problems.append("the START node doesn't lead anywhere.")
			_:
				if node.next_nodes.is_empty():
					problems.append("'%s' is a dead end (it must lead somewhere)." % node.id)
		if node.has_encounter() and (node.encounter == null or node.encounter.enemies.is_empty()):
			problems.append("the battle '%s' has no encounter or no enemies." % node.id)

	# Cycles
	if _topological_order().size() < nodes.size():
		problems.append("the graph contains a cycle (it must be a DAG).")

	# Everything reachable from the start
	var start := get_start()
	if start != null:
		var reached := {start.id: true}
		var to_visit: Array[StringName] = [start.id]
		while not to_visit.is_empty():
			for next_id in get_node_by_id(to_visit.pop_back()).next_nodes:
				if seen.has(next_id) and not reached.has(next_id):
					reached[next_id] = true
					to_visit.append(next_id)
		for node in nodes:
			if not reached.has(node.id):
				problems.append("'%s' can't be reached from the start." % node.id)

	return problems


func _print_validation() -> void:
	var problems := validate()
	if problems.is_empty():
		print("Expedition '%s': the graph is valid (%d nodes)." % [display_name, nodes.size()])
		return
	for problem in problems:
		push_warning("Expedition '%s': %s" % [display_name, problem])


# ---------------------------------------------------------------------------
# Graph helpers
# ---------------------------------------------------------------------------

func _count_unique(ids: Array[StringName]) -> int:
	var unique := {}
	for id in ids:
		unique[id] = true
	return unique.size()


## Nodes ordered so that every node comes after the ones leading to it (Kahn's
## algorithm). Shorter than `nodes` when the graph has a cycle.
func _topological_order() -> Array[StringName]:
	var incoming := {}
	for node in nodes:
		incoming[node.id] = 0
	for node in nodes:
		for next_id in node.next_nodes:
			if incoming.has(next_id):
				incoming[next_id] += 1

	var ready: Array[StringName] = []
	for node in nodes:
		if incoming[node.id] == 0:
			ready.append(node.id)

	var order: Array[StringName] = []
	while not ready.is_empty():
		var current: StringName = ready.pop_back()
		order.append(current)
		for next_id in get_node_by_id(current).next_nodes:
			if not incoming.has(next_id):
				continue
			incoming[next_id] -= 1
			if incoming[next_id] == 0:
				ready.append(next_id)
	return order
