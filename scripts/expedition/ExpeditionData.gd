@tool
class_name ExpeditionData
extends Resource
## An expedition: a destination and the graph (a DAG) of nodes leading to its end.
## There is one START node, and one or more END nodes (several ends allow secret objectives).
## Author it in the inspector: add nodes to `nodes`, link them with `next_nodes`, then
## press the "Validate graph" button to check it.

enum LockedDisplay { HIDDEN, TEASED }

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
## What the player is trying to achieve (shown in the gate menu).
@export_multiline var goal: String = ""
## Extra resources given when the expedition is completed (an END node reached).
## Failing or abandoning keeps the loot gathered on the way but not this bonus.
@export var completion_bonus: Dictionary[StringName, int] = {}

@export_group("Unlock")
## What the player must have done for this expedition to be available on the world map
## (UnlockCompletedExpedition, UnlockBuildingLevel...). All of them must be met.
## Empty = always available.
@export var unlock_conditions: Array[UnlockCondition] = []
## While it is locked: HIDDEN = not on the map at all, TEASED = a black silhouette with a hint.
@export var locked_display: LockedDisplay = LockedDisplay.TEASED
## Text shown on a teased location. Empty = built from the unlock conditions.
@export_multiline var unlock_hint: String = ""

@export_group("Enemies")
## Tags of the enemies that live here ("forest", "catacombs"...). Generated fights (EncounterData.
## fill_with_pool) pick enemies of the EnemyCatalog that share at least one of these tags.
@export var enemy_tags: Array[StringName] = []
## Threat budget of a battle at the start of the map (depth 0). A harder expedition: a higher base.
@export_range(0, 99) var base_budget: int = 2
## Budget added for each column the node is further from the start (see get_depths).
@export_range(0, 99) var budget_per_depth: int = 2

@export_group("Graph")
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


## Threat budget of a battle node: base + budget per column + the node's own bonus.
## EncounterGenerator spends it on enemies.
func get_budget(node: ExpeditionNode) -> int:
	var depth: int = get_depths().get(node.id, 0)
	return maxi(base_budget + budget_per_depth * depth + node.difficulty_bonus, 0)


## The enemies of the EnemyCatalog that share a tag with `enemy_tags` (empty if there is no catalog).
func get_enemy_pool() -> Array[CharacterData]:
	var pool: Array[CharacterData] = []
	if not ResourceLoader.exists(EnemyCatalog.PATH):
		return pool
	var catalog := load(EnemyCatalog.PATH) as EnemyCatalog
	if catalog != null:
		pool.append_array(catalog.get_pool(enemy_tags))
	return pool


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

## Returns the list of problems found (empty = the expedition is valid).
func validate() -> Array[String]:
	var problems: Array[String] = []
	_by_id.clear()

	for condition in unlock_conditions:
		if condition == null:
			problems.append("an entry of `unlock_conditions` is empty.")

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
		if node.has_encounter():
			if node.encounter == null:
				problems.append("the battle '%s' has no encounter." % node.id)
			elif node.encounter.enemies.is_empty() and not node.encounter.fill_with_pool:
				problems.append("the battle '%s' has no enemies (add some, or tick fill_with_pool)." % node.id)

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

	if problems.is_empty():
		problems.append_array(_validate_generated_fights())
	return problems


## Checks the battles that use fill_with_pool: there must be enemies for the tags, and a
## fight without fixed enemies must have a budget that pays for at least the cheapest one.
func _validate_generated_fights() -> Array[String]:
	var problems: Array[String] = []
	var generated: Array[ExpeditionNode] = []
	for node in nodes:
		if node.has_encounter() and node.encounter != null and node.encounter.fill_with_pool:
			generated.append(node)
	if generated.is_empty():
		return problems

	if not ResourceLoader.exists(EnemyCatalog.PATH):
		problems.append("fill_with_pool is used but there is no enemy catalog at %s (run tools/make_enemy_catalog.gd)." % EnemyCatalog.PATH)
		return problems
	var pool := get_enemy_pool()
	if pool.is_empty():
		problems.append("fill_with_pool is used but no enemy of the catalog has any of the enemy_tags %s." % [enemy_tags])
		return problems

	var cheapest: int = pool[0].threat
	for enemy in pool:
		cheapest = mini(cheapest, enemy.threat)
	for node in generated:
		var budget := get_budget(node)
		if node.encounter.enemies.is_empty() and budget < cheapest:
			problems.append("the budget of '%s' (%d) can't pay the cheapest enemy (%d): it will be a single enemy." % [
				node.id, budget, cheapest])
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
	for _id in ids:
		unique[_id] = true
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
