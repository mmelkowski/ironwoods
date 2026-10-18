class_name RunState
extends RefCounted
## The expedition in progress: the team, where it is on the map, the health of
## the heroes and the loot gathered so far. It is thrown away when the
## expedition ends. Plain data only (ids, numbers, lists) so a run can be saved
## in the middle and resumed.

var expedition_id: StringName
var team: Array[StringName] = []           # hero ids, in team order
var hero_health: Dictionary = {}           # hero id -> current health (carries over between battles)
var current_node_id: StringName = &""      # empty until the first node is entered
## False while the content of the current node (battle, camp, event) is not finished.
## The player can only pick the next node once it is resolved, and a saved run
## resumes the unfinished node.
var node_resolved: bool = true
var visited_nodes: Array[StringName] = []
var loot: Dictionary = {}                  # resource id -> amount (always kept, even if the run fails)


## Starts a run: the heroes begin at full health.
static func start(expedition: StringName, heroes: Array[CharacterData]) -> RunState:
	var run := RunState.new()
	run.expedition_id = expedition
	for hero in heroes:
		run.team.append(hero.id)
		run.hero_health[hero.id] = hero.max_health  # TODO: add the forge's health upgrades
	return run


## The player goes to a node: it has to be resolved before moving on.
func enter_node(node_id: StringName) -> void:
	current_node_id = node_id
	visited_nodes.append(node_id)
	node_resolved = false


## The content of the current node is done: the player may pick the next node.
func resolve_node() -> void:
	node_resolved = true


func get_health(hero_id: StringName) -> int:
	return hero_health.get(hero_id, 0)


func set_health(hero_id: StringName, value: int) -> void:
	hero_health[hero_id] = maxi(value, 0)


func add_loot(resource_id: StringName, amount: int) -> void:
	loot[resource_id] = loot.get(resource_id, 0) + amount
