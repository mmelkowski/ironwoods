extends Node
## AUTOLOAD (Project Settings > Globals > Autoload, name: GameState).
## Holds the player's profile and the expedition in progress, does the lookups
## between ids and heroes, and saves / loads the game. Don't give this script a
## class_name: it would clash with the autoload name.

const HERO_CATALOG_PATH := "res://data/hero_catalog.tres"
const EXPEDITION_CATALOG_PATH := "res://data/expedition_catalog.tres"
const BUILDING_CATALOG_PATH := "res://data/building_catalog.tres"

var hero_catalog: HeroCatalog
var expeditions: ExpeditionCatalog
var buildings: BuildingCatalog
var profile: PlayerProfile
var run: RunState  # null when no expedition is in progress

## Saving only happens once a game was started from the main menu (new game or
## loaded). Without this, running the hub scene on its own (F6) with its test
## profile would never touch the real saves.
var can_save := false
## The saved game being played: every save goes into this file.
var save_slot := ""
var save_name := ""
## Why the last load_game() failed (the main menu shows it).
var load_error := ""


func _ready() -> void:
	hero_catalog = load(HERO_CATALOG_PATH) as HeroCatalog
	if hero_catalog == null:
		push_error("GameState: no HeroCatalog found at %s" % HERO_CATALOG_PATH)
		hero_catalog = HeroCatalog.new()
	hero_catalog.validate()

	expeditions = load(EXPEDITION_CATALOG_PATH) as ExpeditionCatalog
	if expeditions == null:
		push_error("GameState: no ExpeditionCatalog found at %s" % EXPEDITION_CATALOG_PATH)
		expeditions = ExpeditionCatalog.new()
	expeditions.validate()

	buildings = load(BUILDING_CATALOG_PATH) as BuildingCatalog
	if buildings == null:
		push_error("GameState: no BuildingCatalog found at %s" % BUILDING_CATALOG_PATH)
		buildings = BuildingCatalog.new()
	buildings.validate()

	# A default profile, so any scene can be run on its own while testing.
	# It is never saved: the main menu replaces it (new game / load).
	_create_profile()


## Starts a fresh game in a new save file: the starting heroes, no resources, no
## expedition. The file is created right away so it shows up in the list of saves.
func new_game(game_name: String = "") -> void:
	_create_profile()
	save_name = game_name.strip_edges()
	if save_name == "":
		save_name = "New game"
	save_slot = SaveManager.new_slot_id()
	can_save = true
	save_game()


func _create_profile() -> void:
	profile = PlayerProfile.new()
	_ensure_starting_heroes()
	_ensure_starting_buildings()
	run = null


# --- Saving ---

## Every saved game, the most recent first (see SaveManager.list_saves).
func list_saves() -> Array[Dictionary]:
	return SaveManager.list_saves()


## The most recently saved game that can be loaded ("" if none).
func latest_save_slot() -> String:
	return SaveManager.latest_slot()


func has_save() -> bool:
	return latest_save_slot() != ""


## Writes the profile and, if there is one, the expedition in progress into the
## current save file. Called at the safe moments: entering the hub, the start of an
## expedition, each time the party is back on the map after a node, the end of an
## expedition. Never in the middle of a battle.
func save_game() -> bool:
	if not can_save or profile == null or save_slot == "":
		return false
	var run_data = null
	if run != null:
		run_data = run.to_dict()
	return SaveManager.write(save_slot, {
		"name": save_name,
		"profile": profile.to_dict(),
		"run": run_data,
	})


## Loads a saved game. From now on, saves go into that file.
## Returns false if it can't be loaded; `load_error` then says why.
func load_game(slot_id: String) -> bool:
	load_error = ""
	var result := SaveManager.read(slot_id)
	if not result["ok"]:
		load_error = result["error"]
		push_warning("GameState: couldn't load '%s' (%s)." % [slot_id, load_error])
		return false

	var data: Dictionary = result["data"]
	var saved_profile: Variant = data.get("profile")
	if not saved_profile is Dictionary:
		load_error = "the save has no player data"
		return false

	profile = PlayerProfile.from_dict(saved_profile)
	_ensure_starting_heroes()  # heroes added to the game after the save was made
	_ensure_starting_buildings()  # saves from before the hub buildings existed get them too
	run = null
	var saved_run: Variant = data.get("run")
	if saved_run is Dictionary:
		var loaded_run := RunState.from_dict(saved_run)
		if _is_run_valid(loaded_run):
			run = loaded_run
	save_slot = slot_id
	save_name = str(data.get("name", "Old save"))
	can_save = true
	return true


## A saved run is only resumed if everything it refers to still exists in the game
## data. The warning says what is missing.
func _is_run_valid(candidate: RunState) -> bool:
	var expedition := expeditions.get_expedition(candidate.expedition_id)
	if expedition == null:
		push_warning("GameState: the saved expedition '%s' doesn't exist, the run was dropped." % candidate.expedition_id)
		return false
	if candidate.team.is_empty():
		push_warning("GameState: the saved run has no team, it was dropped.")
		return false
	for hero_id in candidate.team:
		if hero_catalog.get_hero(hero_id) == null:
			push_warning("GameState: the saved run uses an unknown hero '%s', it was dropped." % hero_id)
			return false
	if candidate.current_node_id != &"" and expedition.get_node_by_id(candidate.current_node_id) == null:
		push_warning("GameState: the saved node '%s' doesn't exist, the run was dropped." % candidate.current_node_id)
		return false
	return true


# --- Heroes ---

## The heroes the player owns (catalog order).
func get_unlocked_heroes() -> Array[CharacterData]:
	var result: Array[CharacterData] = []
	for hero in hero_catalog.heroes:
		if hero.team == CharacterData.Team.ALLY and profile.is_hero_unlocked(hero.id):
			result.append(hero)
	return result


## The heroes of the current expedition, in team order.
func get_run_team() -> Array[CharacterData]:
	var result: Array[CharacterData] = []
	if run == null:
		return result
	for id in run.team:
		var hero := hero_catalog.get_hero(id)
		if hero != null:
			result.append(hero)
	return result


## The heroes of the run who can fight now (the ones that are not down).
func get_run_fighters() -> Array[CharacterData]:
	var result: Array[CharacterData] = []
	for hero in get_run_team():
		if run.is_hero_alive(hero.id):
			result.append(hero)
	return result


# --- Hub buildings ---

## The level of a building: 0 = not built.
func get_building_level(building_id: StringName) -> int:
	return profile.get_upgrade_level(building_id)


## True when the buildings it needs are built to the required level.
func are_requirements_met(building: BuildingData) -> bool:
	for required_id in building.requires:
		if get_building_level(required_id) < building.requires[required_id]:
			return false
	return true


## The next level of a building (its construction if it isn't built). Null at max level.
func get_next_building_level(building: BuildingData) -> BuildingLevel:
	return building.get_level_data(get_building_level(building.id) + 1)


func can_upgrade_building(building: BuildingData) -> bool:
	var next := get_next_building_level(building)
	return next != null and are_requirements_met(building) and profile.can_afford(next.cost)


## Builds or upgrades a building: pays the cost, raises the level, makes it appear in the
## hub, and saves. Returns false (and takes nothing) if it isn't possible.
func upgrade_building(building: BuildingData) -> bool:
	if not can_upgrade_building(building):
		return false
	var next := get_next_building_level(building)
	var new_level := get_building_level(building.id) + 1
	profile.spend(next.cost)
	profile.set_upgrade_level(building.id, new_level)
	profile.unlock_location(building.id)
	save_game()
	return true


## The heroes every game starts with (CharacterData.unlocked_by_default). Also run when a save
## is loaded, so a hero added to the catalog later shows up in old saves too.
func _ensure_starting_heroes() -> void:
	for hero in hero_catalog.heroes:
		if hero.unlocked_by_default and not profile.is_hero_unlocked(hero.id):
			profile.unlock_hero(hero.id)


## The buildings every game starts with (the gate, the carpentry workshop...).
func _ensure_starting_buildings() -> void:
	for building in buildings.buildings:
		if building.built_at_start and not profile.is_location_unlocked(building.id):
			profile.unlock_location(building.id)
			profile.set_upgrade_level(building.id, 1)


# --- Expedition ---

func has_run() -> bool:
	return run != null


## The expedition of the current run.
func get_run_expedition() -> ExpeditionData:
	if run == null:
		return null
	return expeditions.get_expedition(run.expedition_id)


func start_run(expedition_id: StringName, team: Array[CharacterData]) -> void:
	run = RunState.start(expedition_id, team)


## Ends the expedition. There is no penalty for failing or abandoning: all the loot
## gathered is kept. Completing the expedition adds its completion bonus.
## The result is saved. Returns { "loot": {...}, "bonus": {...} } (for the summary screen).
func end_run(completed: bool) -> Dictionary:
	if run == null:
		return {"loot": {}, "bonus": {}}

	var loot := run.loot.duplicate()
	var bonus := {}
	if completed:
		var expedition := get_run_expedition()
		if expedition != null:
			bonus = expedition.completion_bonus.duplicate()

	for id in loot:
		profile.add_resource(id, loot[id])
	for id in bonus:
		profile.add_resource(id, bonus[id])
	run = null
	save_game()
	return {"loot": loot, "bonus": bonus}
