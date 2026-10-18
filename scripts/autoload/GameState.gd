extends Node
## AUTOLOAD (Project Settings > Globals > Autoload, name: GameState).
## Holds the player's profile and the expedition in progress, and does the
## lookups between ids and heroes. Don't give this script a class_name: it
## would clash with the autoload name.

const HERO_CATALOG_PATH := "res://data/hero_catalog.tres"
const EXPEDITION_CATALOG_PATH := "res://data/expedition_catalog.tres"

var hero_catalog: HeroCatalog
var expeditions: ExpeditionCatalog
var profile: PlayerProfile
var run: RunState  # null when no expedition is in progress


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

	# A default profile, so any scene can be run on its own while testing.
	# The main menu replaces it (new game / load).
	new_game()


func new_game() -> void:
	profile = PlayerProfile.new()
	for hero in hero_catalog.heroes:
		if hero.unlocked_by_default:
			profile.unlock_hero(hero.id)
	run = null


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
	print("GameState: run started with ", run.team)  # debug, can be removed


## Ends the expedition. There is no penalty for failing or abandoning: all the loot
## gathered is kept. Completing the expedition adds its completion bonus.
## Returns { "loot": {...}, "bonus": {...} } (for the summary screen).
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
	return {"loot": loot, "bonus": bonus}
