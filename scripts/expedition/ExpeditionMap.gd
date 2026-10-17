class_name ExpeditionMap
extends Control
## Draws the graph of an expedition: one button per node, a line per link.
## Put it inside a ScrollContainer: it sizes itself to fit the whole graph.
##
## Layout: the column of a node is its depth in the graph (longest path from the
## start), its height comes from the node's `lane`. If nodes of one column are
## too close, they are spread evenly.

signal node_chosen(node: ExpeditionNode)

const COLUMN_SPACING := 150.0
const MAP_HEIGHT := 280.0
const MARGIN := Vector2(80.0, 50.0)  # space around the graph
const MIN_LANE_GAP := 0.25           # closer lanes than this get spread out

const LINK_WIDTH := 3.0
const LINK_DIM := Color(1, 1, 1, 0.15)          # a road not taken (yet)
const LINK_TAKEN := Color(1, 1, 1, 0.6)         # the road already walked
const LINK_AVAILABLE := Color(1.0, 0.85, 0.3, 0.9)  # the roads to choose from

var _expedition: ExpeditionData
var _buttons: Dictionary = {}   # node id -> ExpeditionNodeButton
var _centers: Dictionary = {}   # node id -> Vector2 (center of the node)
var _current_id: StringName = &""
var _visited: Array[StringName] = []
var _available: Array[StringName] = []


## Creates the buttons and lays the graph out.
func build(expedition: ExpeditionData) -> void:
	_expedition = expedition
	for button in _buttons.values():
		button.queue_free()
	_buttons.clear()
	_centers.clear()

	_compute_layout()
	for node in expedition.nodes:
		var button := ExpeditionNodeButton.new()
		button.setup(node)
		button.position = _centers[node.id] - ExpeditionNodeButton.SIZE / 2.0
		button.pressed.connect(node_chosen.emit.bind(node))
		add_child(button)
		_buttons[node.id] = button
	queue_redraw()


## Updates the look of every node from the run: visited, current, reachable, locked.
func refresh(run: RunState) -> void:
	_current_id = run.current_node_id
	_visited = run.visited_nodes
	_available.clear()
	if run.node_resolved:  # the next road can only be chosen once the node is done
		for next in _expedition.get_next_nodes(run.current_node_id):
			_available.append(next.id)

	for node_id in _buttons:
		var state := ExpeditionNodeButton.State.LOCKED
		if node_id == _current_id:
			state = ExpeditionNodeButton.State.CURRENT
		elif _visited.has(node_id):
			state = ExpeditionNodeButton.State.VISITED
		elif _available.has(node_id):
			state = ExpeditionNodeButton.State.REACHABLE
		_buttons[node_id].set_state(state)
	queue_redraw()


func get_button(node_id: StringName) -> ExpeditionNodeButton:
	return _buttons.get(node_id)


func _draw() -> void:
	if _expedition == null:
		return
	for node in _expedition.nodes:
		for next_id in node.next_nodes:
			if not _centers.has(next_id):
				continue
			var color := LINK_DIM
			if _visited.has(node.id) and _visited.has(next_id):
				color = LINK_TAKEN
			elif node.id == _current_id and _available.has(next_id):
				color = LINK_AVAILABLE
			draw_line(_centers[node.id], _centers[next_id], color, LINK_WIDTH, true)


func _compute_layout() -> void:
	var depths := _expedition.get_depths()

	# Group the nodes by column
	var columns := {}  # depth -> Array of ExpeditionNode
	var last_depth := 0
	for node in _expedition.nodes:
		var depth: int = depths.get(node.id, 0)
		last_depth = maxi(last_depth, depth)
		if not columns.has(depth):
			columns[depth] = []
		columns[depth].append(node)

	var usable_height := MAP_HEIGHT - 2.0 * MARGIN.y
	for depth in columns:
		var column: Array = columns[depth]
		column.sort_custom(func(a, b): return a.lane < b.lane)

		# Nodes whose lanes are too close would overlap: spread the column evenly
		var crowded := false
		for i in range(1, column.size()):
			if column[i].lane - column[i - 1].lane < MIN_LANE_GAP:
				crowded = true
		for i in column.size():
			var lane: float = column[i].lane
			if crowded:
				lane = lerpf(-0.7, 0.7, float(i) / (column.size() - 1))
			_centers[column[i].id] = Vector2(
				MARGIN.x + depth * COLUMN_SPACING,
				MARGIN.y + (lane * 0.5 + 0.5) * usable_height)

	custom_minimum_size = Vector2(2.0 * MARGIN.x + last_depth * COLUMN_SPACING, MAP_HEIGHT)
