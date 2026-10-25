@tool
class_name EncounterGenerator
extends RefCounted
## Chooses the enemies of a battle node.
##
## - Hand-made encounter (fill_with_pool off): exactly EncounterData.enemies, as before.
## - Generated (fill_with_pool on): EncounterData.enemies are always there (a boss...), then
##   enemies of the expedition's pool are added until the node's threat budget is spent
##   or the battle is full.
##
## budget = expedition.get_budget(node) = base_budget + budget_per_depth * node depth + node.difficulty_bonus
## An enemy costs its `threat`, so a strong enemy only appears once the budget can pay for it.
##
## The result depends only on the run's seed and the node id: the same node always gives the
## same enemies during one run (reloading a save can't reroll a fight), and different runs differ.

## Several random compositions are tried, the one that spends the most budget is kept.
const ATTEMPTS := 8
const DEFAULT_MAX_ENEMIES := 6


static func load_catalog() -> EnemyCatalog:
	if not ResourceLoader.exists(EnemyCatalog.PATH):
		push_error("EncounterGenerator: no EnemyCatalog at %s (run tools/make_enemy_catalog.gd)." % EnemyCatalog.PATH)
		return EnemyCatalog.new()
	var catalog := load(EnemyCatalog.PATH) as EnemyCatalog
	if catalog == null:
		push_error("EncounterGenerator: %s is not an EnemyCatalog." % EnemyCatalog.PATH)
		return EnemyCatalog.new()
	return catalog


## The enemies to spawn for `node`. `max_enemies` is how many the battle can place
## (Battle passes the number of enemy spawn markers).
static func build_enemies(expedition: ExpeditionData, node: ExpeditionNode, run_seed: int,
		max_enemies: int = DEFAULT_MAX_ENEMIES) -> Array[CharacterData]:
	var result: Array[CharacterData] = []
	var encounter := node.encounter
	if encounter == null:
		return result
	result.append_array(encounter.enemies)
	if not encounter.fill_with_pool:
		return result

	var budget := expedition.get_budget(node)
	for enemy in result:
		budget -= enemy.threat

	var pool := expedition.get_enemy_pool()
	if pool.is_empty():
		push_warning("EncounterGenerator: '%s' uses fill_with_pool but no enemy matches the tags %s of '%s'." % [
			node.id, expedition.enemy_tags, expedition.id])
	else:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("%d:%s" % [run_seed, node.id])
		result.append_array(_fill(pool, budget, max_enemies - result.size(), rng))
		if result.is_empty():  # budget too low for anything: never an empty battle
			result.append(_cheapest(pool))

	if OS.is_debug_build():
		print("Encounter '%s': budget %d -> %s" % [node.id, expedition.get_budget(node), _names(result)])
	return result


## Random enemies of the pool whose total threat fits the budget, at most `slots` of them.
static func _fill(pool: Array[CharacterData], budget: int, slots: int, rng: RandomNumberGenerator) -> Array[CharacterData]:
	var best: Array[CharacterData] = []
	var best_spent := -1
	for _attempt in ATTEMPTS:
		var picked: Array[CharacterData] = []
		var remaining := budget
		while picked.size() < slots:
			var affordable: Array[CharacterData] = []
			for enemy in pool:
				if enemy.threat <= remaining:
					affordable.append(enemy)
			if affordable.is_empty():
				break
			var choice := affordable[rng.randi_range(0, affordable.size() - 1)]
			picked.append(choice)
			remaining -= choice.threat
		if budget - remaining > best_spent:
			best = picked
			best_spent = budget - remaining
	return best


static func _cheapest(pool: Array[CharacterData]) -> CharacterData:
	var best := pool[0]
	for enemy in pool:
		if enemy.threat < best.threat:
			best = enemy
	return best


static func _names(enemies: Array[CharacterData]) -> String:
	var names: Array[String] = []
	for enemy in enemies:
		names.append(String(enemy.id))
	return ", ".join(names)
