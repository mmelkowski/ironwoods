@tool
class_name EnemyCatalog
extends Resource
## Every enemy the encounter generator may pick from. One .tres (res://data/enemy_catalog.tres),
## built by tools/make_enemy_catalog.gd or filled by hand. Enemies used only in hand-made
## encounters (EncounterData.enemies) don't have to be here.

const PATH := "res://data/enemy_catalog.tres"

@export var enemies: Array[CharacterData] = []


func get_enemy(enemy_id: StringName) -> CharacterData:
	for enemy in enemies:
		if enemy != null and enemy.id == enemy_id:
			return enemy
	return null


## The enemies that share at least one tag with `tags` (an expedition's enemy_tags).
func get_pool(tags: Array[StringName]) -> Array[CharacterData]:
	var result: Array[CharacterData] = []
	for enemy in enemies:
		if enemy == null or enemy.team != CharacterData.Team.ENEMY:
			continue
		for tag in enemy.tags:
			if tags.has(tag):
				result.append(enemy)
				break
	return result


## Checks the catalog. Pushes a warning for each problem and returns the list.
func validate() -> Array[String]:
	var problems: Array[String] = []
	var seen := {}
	for enemy in enemies:
		if enemy == null:
			problems.append("an entry of `enemies` is empty.")
			continue
		if enemy.id == &"":
			problems.append("an enemy (%s) has no id." % enemy.display_name)
		elif seen.has(enemy.id):
			problems.append("the id '%s' is used by several enemies." % enemy.id)
		seen[enemy.id] = true
		if enemy.team != CharacterData.Team.ENEMY:
			problems.append("'%s' is not on the ENEMY team." % enemy.id)
		if enemy.threat < 1:
			problems.append("'%s' has a threat below 1." % enemy.id)
	for problem in problems:
		push_warning("EnemyCatalog: %s" % problem)
	return problems
