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
## Written by the battle when it ends; read by the expedition screen when the party comes back.
enum BattleResult { NONE, VICTORY, DEFEAT }
var battle_result: BattleResult = BattleResult.NONE
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
	battle_result = BattleResult.NONE


## The content of the current node is done: the player may pick the next node.
func resolve_node() -> void:
	node_resolved = true


func get_health(hero_id: StringName) -> int:
	return hero_health.get(hero_id, 0)


## A hero at 0 health is down: he sits out the battles until a camp heals him.
func is_hero_alive(hero_id: StringName) -> bool:
	return get_health(hero_id) > 0


func set_health(hero_id: StringName, value: int) -> void:
	hero_health[hero_id] = maxi(value, 0)


func add_loot(resource_id: StringName, amount: int) -> void:
	loot[resource_id] = loot.get(resource_id, 0) + amount


# --- Saving ---

func to_dict() -> Dictionary:
	return {
		"expedition_id": String(expedition_id),
		"team": SaveUtils.to_strings(team),
		"hero_health": SaveUtils.dict_to_json(hero_health),
		"current_node_id": String(current_node_id),
		"visited_nodes": SaveUtils.to_strings(visited_nodes),
		"node_resolved": node_resolved,
		"battle_result": int(battle_result),
		"loot": SaveUtils.dict_to_json(loot),
	}


static func from_dict(data: Dictionary) -> RunState:
	var run := RunState.new()
	run.expedition_id = StringName(data.get("expedition_id", ""))
	run.team = SaveUtils.to_names(data.get("team"))
	run.hero_health = SaveUtils.int_dict_from_json(data.get("hero_health"))
	run.current_node_id = StringName(data.get("current_node_id", ""))
	run.visited_nodes = SaveUtils.to_names(data.get("visited_nodes"))
	run.node_resolved = bool(data.get("node_resolved", true))
	var result := int(data.get("battle_result", 0))
	run.battle_result = clampi(result, 0, 2) as BattleResult
	run.loot = SaveUtils.int_dict_from_json(data.get("loot"))
	return run
