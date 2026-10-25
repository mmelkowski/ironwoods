@tool
extends EditorScript
## One-shot helper that builds the first test expedition and registers it in the
## expedition catalog. Open this script in the script editor and use
## File > Run (Ctrl+Shift+X). Running it again overwrites the test expedition.
##
## Run tools/make_enemy_catalog.gd first (and give your enemies tags and a threat):
## the ordinary fights are generated from the enemies of the catalog.
##
## Graph:  start -> fight_1 -+-> fight_hard (+3 budget) -+-> fight_2 -> boss -> end
##                           '-> camp (rest) ------------'
##
## - Ordinary battles share data/encounters/standard_fight.tres (generated enemies, forest tags).
## - The boss is a hobgoblin plus escorts picked with what is left of the budget.
## - Budget of a battle = BASE_BUDGET + BUDGET_PER_DEPTH * its column on the map (+ its bonus).

const EXPEDITION_PATH := "res://data/expeditions/test_expedition.tres"
const CATALOG_PATH := "res://data/expedition_catalog.tres"
const STANDARD_FIGHT_PATH := "res://data/encounters/standard_fight.tres"
const BOSS_PATH := "res://data/character/enemies/hobgoblin.tres"
const FALLBACK_BOSS_PATH := "res://data/character/enemies/goblin.tres"  # used if there is no hobgoblin

const ENEMY_TAGS: Array[StringName] = [&"forest"]
const BASE_BUDGET := 2
const BUDGET_PER_DEPTH := 2
const HARD_BONUS := 3


func _run() -> void:
	var boss := load(BOSS_PATH) as CharacterData
	if boss == null:
		push_warning("make_test_expedition: no boss at %s, using the goblin instead." % BOSS_PATH)
		boss = load(FALLBACK_BOSS_PATH) as CharacterData
	if boss == null:
		push_error("make_test_expedition: no enemy found at %s or %s" % [BOSS_PATH, FALLBACK_BOSS_PATH])
		return
	if not ResourceLoader.exists(EnemyCatalog.PATH):
		push_warning("make_test_expedition: no enemy catalog yet, run tools/make_enemy_catalog.gd first.")

	var standard := _get_standard_fight()
	if standard == null:
		return

	var boss_fight := EncounterData.new()  # the boss is always there, escorts fill the budget
	boss_fight.enemies.append(boss)
	boss_fight.fill_with_pool = true

	var expedition := ExpeditionData.new()
	expedition.id = &"first_expedition"  # the id the gate menu launches for now
	expedition.display_name = "The Old Road"
	expedition.description = "A test expedition."
	expedition.goal = "Reach the end of the road."
	expedition.completion_bonus[&"wood"] = 5
	expedition.completion_bonus[&"stone"] = 3
	expedition.enemy_tags.append_array(ENEMY_TAGS)
	expedition.base_budget = BASE_BUDGET
	expedition.budget_per_depth = BUDGET_PER_DEPTH

	_add(expedition, &"start", ExpeditionNode.Type.START, "Departure", 0.0, [&"fight_1"])
	_add(expedition, &"fight_1", ExpeditionNode.Type.BATTLE, "Ambush on the road", 0.0,
		[&"fight_hard", &"camp"], standard, {&"wood": 3})
	_add(expedition, &"fight_hard", ExpeditionNode.Type.BATTLE, "The goblin patrol", -0.7,
		[&"fight_2"], standard, {&"wood": 2, &"stone": 3}, HARD_BONUS)
	_add(expedition, &"camp", ExpeditionNode.Type.CAMP, "A quiet camp", 0.7, [&"fight_2"])
	_add(expedition, &"fight_2", ExpeditionNode.Type.BATTLE, "The bridge", 0.0,
		[&"boss"], standard, {&"stone": 3, &"wood": 2})
	_add(expedition, &"boss", ExpeditionNode.Type.BOSS, "The goblin chief", 0.0,
		[&"end"], boss_fight, {&"iron": 3, &"stone": 2})
	_add(expedition, &"end", ExpeditionNode.Type.END, "The end of the road", 0.0, [])

	var problems := expedition.validate()
	for problem in problems:
		push_warning("make_test_expedition: %s" % problem)

	DirAccess.make_dir_recursive_absolute("res://data/expeditions")
	if ResourceSaver.save(expedition, EXPEDITION_PATH) != OK:
		push_error("make_test_expedition: couldn't save %s" % EXPEDITION_PATH)
		return
	var saved := ResourceLoader.load(EXPEDITION_PATH, "", ResourceLoader.CACHE_MODE_REPLACE) as ExpeditionData

	# Register it in the catalog (created if needed)
	var catalog: ExpeditionCatalog = null
	if ResourceLoader.exists(CATALOG_PATH):
		catalog = load(CATALOG_PATH) as ExpeditionCatalog
	if catalog == null:
		catalog = ExpeditionCatalog.new()
	for existing in catalog.expeditions.duplicate():
		if existing.id == saved.id:
			catalog.expeditions.erase(existing)
	catalog.expeditions.append(saved)
	ResourceSaver.save(catalog, CATALOG_PATH)

	EditorInterface.get_resource_filesystem().scan()
	print("Test expedition saved (%d problems). Catalog: %s" % [problems.size(), CATALOG_PATH])


## The encounter shared by every ordinary battle: no fixed enemies, filled from the pool.
## Loaded if it exists (so changes you made to it are kept), otherwise created and saved.
## It is always loaded from disk, so the expedition links to the file instead of copying it.
func _get_standard_fight() -> EncounterData:
	if not ResourceLoader.exists(STANDARD_FIGHT_PATH):
		DirAccess.make_dir_recursive_absolute(STANDARD_FIGHT_PATH.get_base_dir())
		var created := EncounterData.new()
		created.fill_with_pool = true
		if ResourceSaver.save(created, STANDARD_FIGHT_PATH) != OK:
			push_error("make_test_expedition: couldn't save %s" % STANDARD_FIGHT_PATH)
			return null
	var standard := load(STANDARD_FIGHT_PATH) as EncounterData
	if standard == null:
		push_error("make_test_expedition: %s is not an EncounterData" % STANDARD_FIGHT_PATH)
	return standard


func _add(expedition: ExpeditionData, id: StringName, type: ExpeditionNode.Type, title: String,
		lane: float, next_ids: Array, encounter: EncounterData = null, loot: Dictionary = {},
		difficulty_bonus: int = 0) -> void:
	var node := ExpeditionNode.new()
	node.id = id
	node.type = type
	node.title = title
	node.lane = lane
	node.encounter = encounter
	node.difficulty_bonus = difficulty_bonus
	for resource_id in loot:
		node.loot[resource_id] = loot[resource_id]
	for next_id in next_ids:
		node.next_nodes.append(next_id)
	expedition.nodes.append(node)
