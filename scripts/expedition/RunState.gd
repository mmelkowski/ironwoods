class_name RunState
extends RefCounted
## The expedition in progress: the team, where it is on the map, the health of
## the heroes and the loot gathered so far. It is thrown away when the
## expedition ends. Plain data only (ids, numbers, lists) so a run can be saved
## in the middle and resumed.

## On defeat the player goes back to the hub with this share of the loot.
const DEFEAT_LOOT_RATIO := 0.5

var expedition_id: StringName
var team: Array[StringName] = []           # hero ids, in team order
var hero_health: Dictionary = {}           # hero id -> current health (carries over between battles)
var current_node_id: StringName = &""      # empty until the first node is entered
var visited_nodes: Array[StringName] = []
var loot: Dictionary = {}                  # resource id -> amount


## Starts a run: the heroes begin at full health.
static func start(expedition: StringName, heroes: Array[CharacterData]) -> RunState:
	var run := RunState.new()
	run.expedition_id = expedition
	for hero in heroes:
		run.team.append(hero.id)
		run.hero_health[hero.id] = hero.max_health  # TODO: add the forge's health upgrades
	return run


func enter_node(node_id: StringName) -> void:
	current_node_id = node_id
	visited_nodes.append(node_id)


func get_health(hero_id: StringName) -> int:
	return hero_health.get(hero_id, 0)


func set_health(hero_id: StringName, value: int) -> void:
	hero_health[hero_id] = maxi(value, 0)


func add_loot(resource_id: StringName, amount: int) -> void:
	loot[resource_id] = loot.get(resource_id, 0) + amount


## What the player keeps: everything after a victory, a share of it after a defeat.
func get_loot_to_keep(victory: bool) -> Dictionary:
	if victory:
		return loot.duplicate()
	var kept := {}
	for id in loot:
		kept[id] = floori(loot[id] * DEFEAT_LOOT_RATIO)
	return kept
