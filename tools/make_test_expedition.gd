@tool
extends EditorScript
## Builds the three fixed debug expeditions and registers them in the expedition catalog.
## Open this script in the script editor and use File > Run (Ctrl+Shift+X). Running it again
## overwrites them. Needs tools/expedition_test_kit.gd (all the paths of the test assets are there).
##
## Run tools/make_enemy_catalog.gd first (and give your enemies tags and a threat): the generated
## fights are built from the enemies of the catalog.
##
##  1. first_expedition  : only the default objective (defeat all enemies), every spawn layout.
##       start -> fight_1 (STANDARD) -+-> fight_hard (AMBUSHED, +3 budget) -+-> fight_2 (AMBUSH) -> boss -> end
##                                    '-> camp ---------------------------'
##  2. test_objectives   : one fight per objective, the boss fight last. No defeat-all.
##       start -> totem (destroy) -> camp_1 -> prisoner (rescue) -> camp_2 -> boss (boss) -> end
##  3. test_catacomb     : 16 nodes with a bit of everything, enemies tagged `catacomb`.
##
## Expedition 2 is skipped (with an error naming what is missing) if a character or the rescue
## card doesn't exist yet. Put an ExpeditionSite on the world map for each id to launch them.

const FIRST_EXPEDITION_ID := &"first_expedition"  # the id the gate menu launches by default
const FIRST_EXPEDITION_PATH := "res://data/expeditions/test_expedition.tres"
const OBJECTIVES_ID := &"test_objectives"
const CATACOMB_ID := &"test_catacomb"

const FOREST_TAGS: Array[StringName] = [&"forest"]
## Must match the tag you give to the catacomb enemies (the ExpeditionData comment says "catacombs").
const CATACOMB_TAGS: Array[StringName] = [&"catacomb"]

const STANDARD := EncounterData.SpawnPattern.STANDARD
const AMBUSH := EncounterData.SpawnPattern.AMBUSH
const AMBUSHED := EncounterData.SpawnPattern.AMBUSHED


func _run() -> void:
	if not ResourceLoader.exists(EnemyCatalog.PATH):
		push_warning("make_test_expedition: no enemy catalog yet, run tools/make_enemy_catalog.gd first.")

	var boss := ExpeditionTestKit.load_boss()
	if boss == null:
		return

	var layouts := _build_layouts(boss)
	if layouts != null:
		ExpeditionTestKit.save_expedition(layouts, FIRST_EXPEDITION_PATH)

	var objectives := _build_objectives(boss)
	if objectives != null:
		ExpeditionTestKit.save_expedition(objectives)

	var catacomb := _build_catacomb(boss)
	if catacomb != null:
		ExpeditionTestKit.save_expedition(catacomb)

	EditorInterface.get_resource_filesystem().scan()
	print("make_test_expedition: done. Warnings above (if any) are the validation of each expedition.")


## 1. Only the default objective, one node per spawn layout.
func _build_layouts(boss: CharacterData) -> ExpeditionData:
	var standard := ExpeditionTestKit.shared_fight(ExpeditionTestKit.STANDARD_FIGHT_PATH, STANDARD)
	var ambush := ExpeditionTestKit.shared_fight(ExpeditionTestKit.AMBUSH_FIGHT_PATH, AMBUSH)
	var ambushed := ExpeditionTestKit.shared_fight(ExpeditionTestKit.AMBUSHED_FIGHT_PATH, AMBUSHED)
	if standard == null or ambush == null or ambushed == null:
		return null
	var boss_fight := ExpeditionTestKit.make_fight([boss])  # no objective scene: defeat all enemies

	var e := ExpeditionTestKit.make_expedition(FIRST_EXPEDITION_ID, "The Old Road",
		"A test expedition.", "Reach the end of the road.", FOREST_TAGS, 2, 2,
		{&"wood": 5, &"stone": 3})
	var kit := ExpeditionTestKit
	kit.add_node(e, &"start", ExpeditionNode.Type.START, "Departure", 0.0, [&"fight_1"])
	kit.add_node(e, &"fight_1", ExpeditionNode.Type.BATTLE, "The road", 0.0,
		[&"fight_hard", &"camp"], standard, {&"wood": 3})
	kit.add_node(e, &"fight_hard", ExpeditionNode.Type.BATTLE, "The goblin patrol", -0.7,
		[&"fight_2"], ambushed, {&"wood": 2, &"stone": 3}, 3)
	kit.add_node(e, &"camp", ExpeditionNode.Type.CAMP, "A quiet camp", 0.7, [&"fight_2"])
	kit.add_node(e, &"fight_2", ExpeditionNode.Type.BATTLE, "The bridge", 0.0,
		[&"boss"], ambush, {&"stone": 3, &"wood": 2})
	kit.add_node(e, &"boss", ExpeditionNode.Type.BOSS, "The goblin chief", 0.0,
		[&"end"], boss_fight, {&"iron": 3, &"stone": 2})
	kit.add_node(e, &"end", ExpeditionNode.Type.END, "The end of the road", 0.0, [])
	return e


## 2. One fight per objective, the boss fight last. Nothing is built if an asset is missing,
## because a fight without its objective would silently become a defeat-all fight.
func _build_objectives(boss: CharacterData) -> ExpeditionData:
	var totem := ExpeditionTestKit.load_character(ExpeditionTestKit.TOTEM_PATH)
	var captor := ExpeditionTestKit.load_character(ExpeditionTestKit.CAPTOR_PATH)
	var hostage := ExpeditionTestKit.load_character(ExpeditionTestKit.HOSTAGE_PATH)
	var missing: Array[String] = []
	if totem == null:
		missing.append(ExpeditionTestKit.TOTEM_PATH)
	if captor == null:
		missing.append(ExpeditionTestKit.CAPTOR_PATH)
	if hostage == null:
		missing.append(ExpeditionTestKit.HOSTAGE_PATH)
	if not missing.is_empty():
		push_error("make_test_expedition: '%s' skipped, these characters don't exist: %s (set the paths in tools/expedition_test_kit.gd)." % [
			OBJECTIVES_ID, ", ".join(missing)])
		return null
	ExpeditionTestKit.check_totem(totem)
	ExpeditionTestKit.check_captor(captor)
	ExpeditionTestKit.check_hostage(hostage)

	var destroy_scene := ExpeditionTestKit.destroy_objective()
	var rescue_scene := ExpeditionTestKit.rescue_objective()
	var boss_scene := ExpeditionTestKit.boss_objective()
	if destroy_scene == null or rescue_scene == null or boss_scene == null:
		push_error("make_test_expedition: '%s' skipped, an objective scene is missing (see the errors above)." % OBJECTIVES_ID)
		return null

	var e := ExpeditionTestKit.make_expedition(OBJECTIVES_ID, "Objective trials",
		"Debug: one fight for each objective, the boss last.", "Pass the three trials.",
		FOREST_TAGS, 3, 1, {&"wood": 5})
	var kit := ExpeditionTestKit
	kit.add_node(e, &"start", ExpeditionNode.Type.START, "Departure", 0.0, [&"totem"])
	kit.add_node(e, &"totem", ExpeditionNode.Type.BATTLE, "The goblin totem", 0.0, [&"camp_1"],
		kit.make_fight([totem], destroy_scene, STANDARD), {&"wood": 2})
	kit.add_node(e, &"camp_1", ExpeditionNode.Type.CAMP, "A short rest", 0.0, [&"prisoner"])
	kit.add_node(e, &"prisoner", ExpeditionNode.Type.BATTLE, "The prisoner", 0.0, [&"camp_2"],
		kit.make_fight([captor, hostage], rescue_scene, STANDARD), {&"stone": 2})
	kit.add_node(e, &"camp_2", ExpeditionNode.Type.CAMP, "Another rest", 0.0, [&"boss"])
	kit.add_node(e, &"boss", ExpeditionNode.Type.BOSS, "The goblin chief", 0.0, [&"end"],
		kit.make_fight([boss], boss_scene, STANDARD), {&"iron": 2})
	kit.add_node(e, &"end", ExpeditionNode.Type.END, "The end", 0.0, [])
	return e


## 3. The long one: branches, every layout, every objective, camps and events.
## Like expedition 2, nothing is built if a character or an objective scene is missing.
func _build_catacomb(boss: CharacterData) -> ExpeditionData:
	var kit := ExpeditionTestKit
	var standard := kit.shared_fight(kit.STANDARD_FIGHT_PATH, STANDARD)
	var ambush := kit.shared_fight(kit.AMBUSH_FIGHT_PATH, AMBUSH)
	var ambushed := kit.shared_fight(kit.AMBUSHED_FIGHT_PATH, AMBUSHED)
	if standard == null or ambush == null or ambushed == null:
		return null

	var totem := kit.load_character(kit.TOTEM_PATH)
	var captor := kit.load_character(kit.CAPTOR_PATH)
	var hostage := kit.load_character(kit.HOSTAGE_PATH)
	if totem == null or captor == null or hostage == null:
		push_error("make_test_expedition: '%s' skipped, the totem, captor or hostage doesn't exist (see tools/expedition_test_kit.gd)." % CATACOMB_ID)
		return null
	var destroy_scene := kit.destroy_objective()
	var rescue_scene := kit.rescue_objective()
	var boss_scene := kit.boss_objective()
	if destroy_scene == null or rescue_scene == null or boss_scene == null:
		push_error("make_test_expedition: '%s' skipped, an objective scene is missing (see the errors above)." % CATACOMB_ID)
		return null

	var e := kit.make_expedition(CATACOMB_ID, "The Catacombs",
		"Debug: a long expedition with a bit of everything, to test the catacomb enemies.",
		"Reach the heart of the catacombs.", CATACOMB_TAGS, 3, 1, {&"wood": 8, &"stone": 5, &"iron": 3})

	kit.add_node(e, &"start", ExpeditionNode.Type.START, "Departure", 0.0, [&"entrance"])
	kit.add_node(e, &"entrance", ExpeditionNode.Type.BATTLE, "The gate of bones", 0.0,
		[&"ossuary", &"shrine"], standard, {&"wood": 2})
	kit.add_node(e, &"ossuary", ExpeditionNode.Type.BATTLE, "The ossuary", -0.7,
		[&"hall"], ambush, {&"stone": 2}, 1)
	kit.add_node(e, &"shrine", ExpeditionNode.Type.EVENT, "A forgotten shrine", 0.7,
		[&"hall"], null, {&"wood": 1})
	kit.add_node(e, &"hall", ExpeditionNode.Type.BATTLE, "The grand hall", 0.0,
		[&"camp_1", &"totem"], ambushed, {&"stone": 2})
	kit.add_node(e, &"camp_1", ExpeditionNode.Type.CAMP, "A candlelit alcove", -0.7, [&"cells"])
	kit.add_node(e, &"totem", ExpeditionNode.Type.BATTLE, "The bone totem", 0.7,
		[&"cells"], kit.make_fight([totem], destroy_scene, AMBUSHED), {&"iron": 1})
	kit.add_node(e, &"cells", ExpeditionNode.Type.BATTLE, "The cells", 0.0,
		[&"bridge"], kit.make_fight([captor, hostage], rescue_scene, STANDARD), {&"stone": 2})
	kit.add_node(e, &"bridge", ExpeditionNode.Type.BATTLE, "The bridge of skulls", 0.0,
		[&"camp_2"], standard, {&"wood": 2})
	kit.add_node(e, &"camp_2", ExpeditionNode.Type.CAMP, "The last quiet place", 0.0,
		[&"vault", &"well"])
	kit.add_node(e, &"vault", ExpeditionNode.Type.BATTLE, "The sealed vault", -0.7,
		[&"reliquary"], ambush, {&"iron": 2}, 2)
	kit.add_node(e, &"well", ExpeditionNode.Type.EVENT, "The whispering well", 0.7,
		[&"reliquary"], null, {&"stone": 1})
	kit.add_node(e, &"reliquary", ExpeditionNode.Type.BATTLE, "The reliquary", 0.0,
		[&"last_stand"], kit.make_fight([totem], destroy_scene, AMBUSH), {&"iron": 2})
	kit.add_node(e, &"last_stand", ExpeditionNode.Type.BATTLE, "The last stand", 0.0,
		[&"boss"], ambushed, {&"stone": 3}, 1)
	kit.add_node(e, &"boss", ExpeditionNode.Type.BOSS, "The catacomb lord", 0.0,
		[&"end"], kit.make_fight([boss], boss_scene, STANDARD), {&"iron": 4})
	kit.add_node(e, &"end", ExpeditionNode.Type.END, "The heart of the catacombs", 0.0, [])
	return e
