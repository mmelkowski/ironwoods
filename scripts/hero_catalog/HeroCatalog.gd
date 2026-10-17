class_name HeroCatalog
extends Resource
## The list of every playable hero, and the lookup from a hero id to its data.
## Create one .tres (data/hero_catalog.tres), drag all the hero .tres files into
## `heroes`. Saves store hero ids, and this catalog turns them back into heroes.

@export var heroes: Array[CharacterData] = []


func get_hero(id: StringName) -> CharacterData:
	for hero in heroes:
		if hero.id == id:
			return hero
	return null


## Warns about heroes that couldn't be saved or found: empty or duplicate ids.
func validate() -> void:
	var seen := {}
	for hero in heroes:
		if hero.id == &"":
			push_warning("HeroCatalog: '%s' has no id (needed for saves)." % hero.display_name)
		elif seen.has(hero.id):
			push_warning("HeroCatalog: the id '%s' is used by several heroes." % hero.id)
		seen[hero.id] = true
