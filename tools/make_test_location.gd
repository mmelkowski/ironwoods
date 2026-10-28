@tool
extends EditorScript
## File > Run (Ctrl+Shift+X) with this script open. Run tools/make_test_expedition.gd first.
##
## Creates two extra test expeditions and registers them in the expedition catalog, to try the
## three looks of a location on the world map:
##   hollow_crypt      : TEASED (black silhouette + hint) until "first_expedition" is completed
##   sunken_watchtower : HIDDEN until the carpentry workshop is level 2
## Both use a simple graph: start -> fight_1 -> fight_2 -> boss -> end, with generated fights.
## Then place an ExpeditionSite for each id on the world map. Running it again overwrites them.

const CATALOG_PATH := "res://data/expedition_catalog.tres"
const STANDARD_FIGHT_PATH := "res://data/encounters/standard_fight.tres"
const BOSS_PATH := "res://data/character/enemies/hobgoblin.tres"
const FIRST_EXPEDITION_ID := &"first_expedition"
const CARPENTRY_ID := &"carpentry"  # the id of the carpentry workshop building (its HubLocation id)
const ENEMY_TAGS: Array[StringName] = [&"forest"]  # no other enemies exist yet: change when they do


func _run() -> void:
	var standard := load(STANDARD_FIGHT_PATH) as EncounterData
	var boss := load(BOSS_PATH) as CharacterData
	if standard == null or boss == null:
		push_error("make_test_locations: run tools/make_test_expedition.gd first (needs %s and %s)." % [
			STANDARD_FIGHT_PATH, BOSS_PATH])
		return

	var crypt := _make_expedition(&"hollow_crypt", "The Hollow Crypt",
		"An old crypt under the hills. Something stirs in the dark.", "Reach the crypt's heart.",
		standard, boss, 4, 3)
	var finished_first := UnlockCompletedExpedition.new()
	finished_first.expedition_id = FIRST_EXPEDITION_ID
	crypt.unlock_conditions.append(finished_first)
	crypt.locked_display = ExpeditionData.LockedDisplay.TEASED
	_save(crypt)

	var tower := _make_expedition(&"sunken_watchtower", "The Sunken Watchtower",
		"A watchtower half swallowed by the marsh.", "Climb to the top of the tower.",
		standard, boss, 6, 3)
	var built_workshop := UnlockBuildingLevel.new()
	built_workshop.building_id = CARPENTRY_ID
	built_workshop.level = 2
	tower.unlock_conditions.append(built_workshop)
	tower.locked_display = ExpeditionData.LockedDisplay.HIDDEN
	_save(tower)

	EditorInterface.get_resource_filesystem().scan()
	print("make_test_locations: done. Place an ExpeditionSite for 'hollow_crypt' and 'sunken_watchtower' on the world map.")


func _make_expedition(id: StringName, title: String, description: String, goal: String,
		standard: EncounterData, boss: CharacterData, base_budget: int, budget_per_depth: int) -> ExpeditionData:
	var boss_fight := EncounterData.new()
	boss_fight.enemies.append(boss)
	boss_fight.fill_with_pool = true

	var expedition := ExpeditionData.new()
	expedition.id = id
	expedition.display_name = title
	expedition.description = description
	expedition.goal = goal
	expedition.completion_bonus[&"wood"] = 8
	expedition.completion_bonus[&"stone"] = 5
	expedition.enemy_tags.append_array(ENEMY_TAGS)
	expedition.base_budget = base_budget
	expedition.budget_per_depth = budget_per_depth

	_add(expedition, &"start", ExpeditionNode.Type.START, "Departure", [&"fight_1"])
	_add(expedition, &"fight_1", ExpeditionNode.Type.BATTLE, "First encounter", [&"fight_2"], standard, {&"wood": 3})
	_add(expedition, &"fight_2", ExpeditionNode.Type.BATTLE, "Second encounter", [&"boss"], standard, {&"stone": 3})
	_add(expedition, &"boss", ExpeditionNode.Type.BOSS, "The guardian", [&"end"], boss_fight, {&"iron": 3})
	_add(expedition, &"end", ExpeditionNode.Type.END, "The end", [])
	return expedition


func _add(expedition: ExpeditionData, id: StringName, type: ExpeditionNode.Type, title: String,
		next_ids: Array, encounter: EncounterData = null, loot: Dictionary = {}) -> void:
	var node := ExpeditionNode.new()
	node.id = id
	node.type = type
	node.title = title
	node.encounter = encounter
	for resource_id in loot:
		node.loot[resource_id] = loot[resource_id]
	for next_id in next_ids:
		node.next_nodes.append(next_id)
	expedition.nodes.append(node)


## Saves the expedition as a clean file, checks it reads back correctly, and registers it in the catalog.
func _save(expedition: ExpeditionData) -> void:
	var path := "res://data/expeditions/%s.tres" % expedition.id
	DirAccess.make_dir_recursive_absolute("res://data/expeditions")
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if ResourceSaver.save(expedition, path) != OK:
		push_error("make_test_locations: couldn't save %s" % path)
		return

	var fresh := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ExpeditionData
	if fresh == null:
		push_error("make_test_locations: %s can't be read back." % path)
		return
	for problem in fresh.validate():
		push_error("make_test_locations: %s is corrupted: %s" % [path, problem])

	var saved := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as ExpeditionData
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
