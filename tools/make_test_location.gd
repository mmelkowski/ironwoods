@tool
extends EditorScript
## File > Run (Ctrl+Shift+X) with this script open. Run tools/make_test_expedition.gd first.
##
## Creates two extra test expeditions and registers them in the expedition catalog, to try the
## three looks of a location on the world map:
##   hollow_crypt      : TEASED (black silhouette + hint) until "first_expedition" is completed
##   sunken_watchtower : HIDDEN until the carpentry workshop is level 2
## Both use a simple graph: start -> fight_1 -> fight_2 -> boss -> end, with generated fights and a
## boss fight that uses the BossObjective. These are for the map's unlock display, not for
## debugging objectives: the debug expeditions (always unlocked) come from make_test_expedition.gd.
## Then place an ExpeditionSite for each id on the world map. Running it again overwrites them.

const FIRST_EXPEDITION_ID := &"first_expedition"
const CARPENTRY_ID := &"carpentry"  # the id of the carpentry workshop building (its HubLocation id)
const ENEMY_TAGS: Array[StringName] = [&"forest"]  # the catacomb enemies are tested in test_catacomb


func _run() -> void:
	var standard := ExpeditionTestKit.shared_fight(ExpeditionTestKit.STANDARD_FIGHT_PATH,
		EncounterData.SpawnPattern.STANDARD)
	var boss := ExpeditionTestKit.load_boss()
	var boss_scene := ExpeditionTestKit.boss_objective()
	if standard == null or boss == null or boss_scene == null:
		push_error("make_test_locations: needs the standard fight, a boss and the boss objective scene (see the errors above, and tools/expedition_test_kit.gd).")
		return

	var crypt := _make_expedition(&"hollow_crypt", "The Hollow Crypt",
		"An old crypt under the hills. Something stirs in the dark.", "Reach the crypt's heart.",
		standard, boss, boss_scene, 4, 3)
	var finished_first := UnlockCompletedExpedition.new()
	finished_first.expedition_id = FIRST_EXPEDITION_ID
	crypt.unlock_conditions.append(finished_first)
	crypt.locked_display = ExpeditionData.LockedDisplay.TEASED
	ExpeditionTestKit.save_expedition(crypt)

	var tower := _make_expedition(&"sunken_watchtower", "The Sunken Watchtower",
		"A watchtower half swallowed by the marsh.", "Climb to the top of the tower.",
		standard, boss, boss_scene, 6, 3)
	var built_workshop := UnlockBuildingLevel.new()
	built_workshop.building_id = CARPENTRY_ID
	built_workshop.level = 2
	tower.unlock_conditions.append(built_workshop)
	tower.locked_display = ExpeditionData.LockedDisplay.HIDDEN
	ExpeditionTestKit.save_expedition(tower)

	EditorInterface.get_resource_filesystem().scan()
	print("make_test_locations: done. Place an ExpeditionSite for 'hollow_crypt' and 'sunken_watchtower' on the world map.")


func _make_expedition(id: StringName, title: String, description: String, goal: String,
		standard: EncounterData, boss: CharacterData, boss_scene: PackedScene,
		base_budget: int, budget_per_depth: int) -> ExpeditionData:
	var kit := ExpeditionTestKit
	var expedition := kit.make_expedition(id, title, description, goal, ENEMY_TAGS,
		base_budget, budget_per_depth, {&"wood": 8, &"stone": 5})
	kit.add_node(expedition, &"start", ExpeditionNode.Type.START, "Departure", 0.0, [&"fight_1"])
	kit.add_node(expedition, &"fight_1", ExpeditionNode.Type.BATTLE, "First encounter", 0.0,
		[&"fight_2"], standard, {&"wood": 3})
	kit.add_node(expedition, &"fight_2", ExpeditionNode.Type.BATTLE, "Second encounter", 0.0,
		[&"boss"], standard, {&"stone": 3})
	kit.add_node(expedition, &"boss", ExpeditionNode.Type.BOSS, "The guardian", 0.0,
		[&"end"], kit.make_fight([boss], boss_scene), {&"iron": 3})
	kit.add_node(expedition, &"end", ExpeditionNode.Type.END, "The end", 0.0, [])
	return expedition
