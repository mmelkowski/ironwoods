@tool
extends EditorScript
## One-shot helper that builds the first test expedition and registers it in the
## expedition catalog. Open this script in the script editor and use
## File > Run (Ctrl+Shift+X). Running it again overwrites the test expedition.
##
## Graph:  start -> fight_1 -+-> fight_hard (2 goblins) -+-> fight_2 -> boss -> end
##                           '-> camp (rest) ------------'

const EXPEDITION_PATH := "res://data/expeditions/test_expedition.tres"
const CATALOG_PATH := "res://data/expedition_catalog.tres"
const GOBLIN_PATH := "res://data/character/enemies/goblin.tres"


func _run() -> void:
	var goblin := load(GOBLIN_PATH) as CharacterData
	if goblin == null:
		push_error("make_test_expedition: no goblin found at %s" % GOBLIN_PATH)
		return

	var expedition := ExpeditionData.new()
	expedition.id = &"first_expedition"  # the id the gate menu launches for now
	expedition.display_name = "The Old Road"
	expedition.description = "A test expedition."
	expedition.goal = "Reach the end of the road."

	_add(expedition, &"start", ExpeditionNode.Type.START, "Departure", 0.0, [&"fight_1"])
	_add(expedition, &"fight_1", ExpeditionNode.Type.BATTLE, "Ambush on the road", 0.0,
		[&"fight_hard", &"camp"], goblin, 2)
	_add(expedition, &"fight_hard", ExpeditionNode.Type.BATTLE, "The goblin patrol", -0.7,
		[&"fight_2"], goblin, 3)
	_add(expedition, &"camp", ExpeditionNode.Type.CAMP, "A quiet camp", 0.7, [&"fight_2"])
	_add(expedition, &"fight_2", ExpeditionNode.Type.BATTLE, "The bridge", 0.0, [&"boss"], goblin, 3)
	_add(expedition, &"boss", ExpeditionNode.Type.BOSS, "The goblin chief", 0.0, [&"end"], goblin, 4)
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


func _add(expedition: ExpeditionData, id: StringName, type: ExpeditionNode.Type, title: String,
		lane: float, next_ids: Array, enemy: CharacterData = null, enemy_count: int = 0) -> void:
	var node := ExpeditionNode.new()
	node.id = id
	node.type = type
	node.title = title
	node.lane = lane
	for next_id in next_ids:
		node.next_nodes.append(next_id)
	if enemy_count > 0:
		node.encounter = EncounterData.new()
		for i in enemy_count:
			node.encounter.enemies.append(enemy)
	expedition.nodes.append(node)
