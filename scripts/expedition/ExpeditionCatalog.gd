class_name ExpeditionCatalog
extends Resource
## The list of every expedition of the game, and the lookup from an expedition id.
## One .tres (data/expedition_catalog.tres) that references the expedition .tres files.

@export var expeditions: Array[ExpeditionData] = []


func get_expedition(id: StringName) -> ExpeditionData:
	for expedition in expeditions:
		if expedition.id == id:
			return expedition
	return null


## Warns about duplicate ids and invalid graphs. Called when the game starts.
func validate() -> void:
	var seen := {}
	for expedition in expeditions:
		if expedition.id == &"":
			push_warning("ExpeditionCatalog: '%s' has no id." % expedition.display_name)
		elif seen.has(expedition.id):
			push_warning("ExpeditionCatalog: the id '%s' is used by several expeditions." % expedition.id)
		seen[expedition.id] = true

		for problem in expedition.validate():
			push_warning("Expedition '%s': %s" % [expedition.display_name, problem])
