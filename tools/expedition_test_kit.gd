@tool
class_name ExpeditionTestKit
extends RefCounted
## Shared helpers of tools/make_test_expedition.gd and tools/make_test_location.gd:
## where the test assets live, loading and checking them, building encounters and nodes,
## and saving + registering an expedition. Static only, nothing to instantiate.
##
## Reminder: scripts that are not @tool (CharacterData, the objectives...) are placeholders in the
## editor: their properties and constants work, their METHODS do not. So this file reads
## `data.roles` and never calls `data.has_role()`.

const CATALOG_PATH := "res://data/expedition_catalog.tres"
const EXPEDITIONS_DIR := "res://data/expeditions"

# --- Shared ordinary fights: no fixed enemies, filled from the pool; one per spawn layout ---
const STANDARD_FIGHT_PATH := "res://data/EncounterData/standard_fight.tres"
const AMBUSH_FIGHT_PATH := "res://data/EncounterData/ambush_fight.tres"    # the heroes surprise the enemies
const AMBUSHED_FIGHT_PATH := "res://data/EncounterData/ambushed_fight.tres"  # the enemies surprise the heroes

# --- Objective scenes: created here if the file doesn't exist, otherwise the existing one is used ---
const BOSS_OBJECTIVE_PATH := "res://scenes/battle/objective/boss_objective.tscn"
const DESTROY_OBJECTIVE_PATH := "res://scenes/battle/objective/destroy_object_objective.tscn"
const RESCUE_OBJECTIVE_PATH := "res://scenes/battle/objective/rescue_objective.tscn"

# --- Characters and card: you author these, the tool only loads and checks them ---
const BOSS_PATH := "res://data/character/enemies/hobgoblin.tres"  # roles: BOSS
const FALLBACK_BOSS_PATH := "res://data/character/enemies/goblin.tres"  # used if there is no hobgoblin
const TOTEM_PATH := "res://data/character/object/totem.tres"  # roles: OBJECT, acts off, can_be_moved off
const CAPTOR_PATH := "res://data/character/enemies/goblin_captor.tres"  # roles: CAPTOR  (adjust the path)
const HOSTAGE_PATH := "res://data/character/neutral/hostage.tres"  # team NEUTRAL, roles: HOSTAGE, acts and can_be_moved off  (adjust the path)
const RESCUE_CARD_PATH := "res://data/cards/hostage/unlock.tres"  # SUPPORT, target SELF, damage 0  (adjust the path)


# ---------------------------------------------------------------------------
# Characters and card
# ---------------------------------------------------------------------------

static func load_character(path: String) -> CharacterData:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as CharacterData


## The boss: the hobgoblin, or the goblin if there is none. Null if neither exists.
static func load_boss() -> CharacterData:
	var boss := load_character(BOSS_PATH)
	if boss == null:
		push_warning("ExpeditionTestKit: no boss at %s, using the goblin instead." % BOSS_PATH)
		boss = load_character(FALLBACK_BOSS_PATH)
	if boss == null:
		push_error("ExpeditionTestKit: no enemy found at %s or %s" % [BOSS_PATH, FALLBACK_BOSS_PATH])
		return null
	if not boss.roles.has(CharacterData.Role.BOSS):
		push_warning("ExpeditionTestKit: '%s' has no BOSS role: a BossObjective fight would fall back to 'defeat all enemies'. Add BOSS to its roles." % boss.display_name)
	return boss


## Warnings only: a wrongly set character would not fail here but misbehave in the battle.
static func check_totem(data: CharacterData) -> void:
	if not data.roles.has(CharacterData.Role.OBJECT):
		push_warning("ExpeditionTestKit: '%s' needs the OBJECT role." % data.display_name)
	if data.acts or data.can_be_moved:
		push_warning("ExpeditionTestKit: '%s' must have `acts` and `can_be_moved` turned off." % data.display_name)


static func check_captor(data: CharacterData) -> void:
	if not data.roles.has(CharacterData.Role.CAPTOR):
		push_warning("ExpeditionTestKit: '%s' needs the CAPTOR role." % data.display_name)


static func check_hostage(data: CharacterData) -> void:
	if data.team != CharacterData.Team.NEUTRAL:
		push_warning("ExpeditionTestKit: '%s' must be on the NEUTRAL team." % data.display_name)
	if not data.roles.has(CharacterData.Role.HOSTAGE):
		push_warning("ExpeditionTestKit: '%s' needs the HOSTAGE role." % data.display_name)
	if data.acts or data.can_be_moved:
		push_warning("ExpeditionTestKit: '%s' must have `acts` and `can_be_moved` turned off." % data.display_name)


# ---------------------------------------------------------------------------
# Encounters
# ---------------------------------------------------------------------------

## An ordinary generated fight shared by many nodes, with the given spawn layout.
## Loaded from disk if it exists (so your changes are kept, and the expedition links to the file
## instead of copying it), otherwise created. Its spawn_pattern is always set to `pattern`.
static func shared_fight(path: String, pattern: EncounterData.SpawnPattern) -> EncounterData:
	if not ResourceLoader.exists(path):
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var created := EncounterData.new()
		created.fill_with_pool = true
		created.spawn_pattern = pattern
		if ResourceSaver.save(created, path) != OK:
			push_error("ExpeditionTestKit: couldn't save %s" % path)
			return null
	var fight := load(path) as EncounterData
	if fight == null:
		push_error("ExpeditionTestKit: %s is not an EncounterData" % path)
		return null
	if fight.spawn_pattern != pattern:
		push_warning("ExpeditionTestKit: %s had another spawn pattern, set back to %s." % [
			path, EncounterData.SpawnPattern.keys()[pattern]])
		fight.spawn_pattern = pattern
		ResourceSaver.save(fight, path)
	return fight


## A fight of its own (stored inside the expedition file): `enemies` are always there and escorts
## fill the rest of the budget. `objective` null = the default objective, defeat all enemies.
static func make_fight(enemies: Array, objective: PackedScene = null,
		pattern: EncounterData.SpawnPattern = EncounterData.SpawnPattern.STANDARD) -> EncounterData:
	var fight := EncounterData.new()
	for enemy in enemies:
		fight.enemies.append(enemy)
	fight.fill_with_pool = true
	fight.objective_scene = objective
	fight.spawn_pattern = pattern
	return fight


# ---------------------------------------------------------------------------
# Objective scenes
# ---------------------------------------------------------------------------

static func boss_objective() -> PackedScene:
	return _objective_scene(BOSS_OBJECTIVE_PATH, func() -> Node: return BossObjective.new())


static func destroy_objective() -> PackedScene:
	return _objective_scene(DESTROY_OBJECTIVE_PATH, func() -> Node: return DestroyObjectObjective.new())


## Needs the rescue card (a new scene gets it assigned). Null if the card is missing.
static func rescue_objective() -> PackedScene:
	if ResourceLoader.exists(RESCUE_OBJECTIVE_PATH):
		return _objective_scene(RESCUE_OBJECTIVE_PATH, Callable())
	if not ResourceLoader.exists(RESCUE_CARD_PATH):
		push_error("ExpeditionTestKit: no rescue card at %s (a SUPPORT card, target SELF, damage 0)." % RESCUE_CARD_PATH)
		return null
	var card := load(RESCUE_CARD_PATH) as CardData
	return _objective_scene(RESCUE_OBJECTIVE_PATH, func() -> Node:
		var objective := RescueObjective.new()
		objective.rescue_card = card
		return objective)


static func _objective_scene(path: String, factory: Callable) -> PackedScene:
	if ResourceLoader.exists(path):
		var existing := load(path) as PackedScene
		if existing == null:
			push_error("ExpeditionTestKit: %s is not a scene." % path)
		return existing
	var root: Node = factory.call()
	root.name = path.get_file().get_basename().to_pascal_case()
	var packed := PackedScene.new()
	var packed_ok := packed.pack(root)
	root.free()
	if packed_ok != OK:
		push_error("ExpeditionTestKit: couldn't pack the objective scene for %s" % path)
		return null
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if ResourceSaver.save(packed, path) != OK:
		push_error("ExpeditionTestKit: couldn't save %s" % path)
		return null
	print("ExpeditionTestKit: created %s" % path)
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene


# ---------------------------------------------------------------------------
# Expeditions
# ---------------------------------------------------------------------------

static func make_expedition(id: StringName, title: String, description: String, goal: String,
		enemy_tags: Array, base_budget: int, budget_per_depth: int,
		completion_bonus: Dictionary = {}) -> ExpeditionData:
	var expedition := ExpeditionData.new()
	expedition.id = id
	expedition.display_name = title
	expedition.description = description
	expedition.goal = goal
	for resource_id in completion_bonus:
		expedition.completion_bonus[resource_id] = completion_bonus[resource_id]
	for tag in enemy_tags:
		expedition.enemy_tags.append(tag)
	expedition.base_budget = base_budget
	expedition.budget_per_depth = budget_per_depth
	return expedition


## `lane`: -1 top ... 1 bottom (map layout hint). `difficulty_bonus`: added to the node's budget.
static func add_node(expedition: ExpeditionData, id: StringName, type: ExpeditionNode.Type,
		title: String, lane: float, next_ids: Array, encounter: EncounterData = null,
		loot: Dictionary = {}, difficulty_bonus: int = 0) -> void:
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


## Saves the expedition as a clean file (the old file is removed first), reads it back, prints what
## validate() finds (warnings) and registers it in the expedition catalog. `path` empty =
## res://data/expeditions/<id>.tres. Returns false if it couldn't be saved.
static func save_expedition(expedition: ExpeditionData, path: String = "") -> bool:
	if path == "":
		path = "%s/%s.tres" % [EXPEDITIONS_DIR, expedition.id]
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if ResourceSaver.save(expedition, path) != OK:
		push_error("ExpeditionTestKit: couldn't save %s" % path)
		return false

	var fresh := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ExpeditionData
	if fresh == null:
		push_error("ExpeditionTestKit: %s can't be read back." % path)
		return false
	var problems := fresh.validate()
	for problem in problems:
		push_warning("ExpeditionTestKit: '%s': %s" % [expedition.id, problem])

	var saved := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as ExpeditionData
	_register(saved)
	print("ExpeditionTestKit: '%s' saved (%d nodes, %d problems) -> %s" % [
		expedition.id, expedition.nodes.size(), problems.size(), path])
	return true


static func _register(saved: ExpeditionData) -> void:
	var catalog: ExpeditionCatalog = null
	if ResourceLoader.exists(CATALOG_PATH):
		catalog = load(CATALOG_PATH) as ExpeditionCatalog
	if catalog == null:
		catalog = ExpeditionCatalog.new()
	for existing in catalog.expeditions.duplicate():
		if existing == null or existing.id == saved.id:
			catalog.expeditions.erase(existing)
	catalog.expeditions.append(saved)
	ResourceSaver.save(catalog, CATALOG_PATH)
