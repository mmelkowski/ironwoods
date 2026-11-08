@tool
extends EditorScript
## File > Run. Creates the sample events (data/events/*.tres) and the event catalog
## (data/event_catalog.tres). Overwrites its outputs when re-run.
##
## Tags are the words of ExpeditionData.enemy_tags: "forest", "catacomb"... An event
## without tag fits every expedition.

const EVENTS_DIR := "res://data/events"


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(EVENTS_DIR)
	var catalog := EventCatalog.new()
	for event in [_lumberyard(), _quarry(), _clearing(), _adventurer(), _sarcophagus()]:
		var saved := _save(event, "%s/%s.tres" % [EVENTS_DIR, event.id])
		if saved != null:
			catalog.events.append(saved)

	_save(catalog, EventCatalog.PATH)
	var problems := catalog.validate()
	for problem in problems:
		push_warning("make_events: %s" % problem)
	if problems.is_empty():
		print("make_events: %d events written, catalog valid." % catalog.events.size())
	EditorInterface.get_resource_filesystem().scan()


# ---------------------------------------------------------------------------
# The events
# ---------------------------------------------------------------------------

func _lumberyard() -> EventData:
	var pay := EventSpendLoot.new()
	pay.cost = _loot({&"stone": 2})
	var gain := EventGainLoot.new()
	gain.loot = _loot({&"wood": 4})
	return _event(&"lumberyard", "The Lumberyard",
		"A man guards a pile of freshly cut logs. \"Stone is hard to come by out here,\" he says. \"Give me two and I'll give you four loads of wood.\"",
		[&"forest"], [
			_choice("Trade", "The lumberjack grins and helps you load the logs.", [pay, gain]),
			_choice("Walk away", "You nod and go on your way.", []),
		])


func _quarry() -> EventData:
	var pay := EventSpendLoot.new()
	pay.cost = _loot({&"wood": 2})
	var gain := EventGainLoot.new()
	gain.loot = _loot({&"stone": 4})
	return _event(&"quarry", "The Quarry",
		"Hammers ring against the rock. A foreman waves you over. \"We are short of timber for the supports. Two bundles of wood, and I'll pay you four blocks of stone.\"",
		[&"forest", &"mountain"], [
			_choice("Trade", "The foreman has your stone carried over.", [pay, gain]),
			_choice("Walk away", "You leave the workers to their business.", []),
		])


func _clearing() -> EventData:
	var heal := EventHealParty.new()
	heal.amount = 15
	return _event(&"clearing", "A Quiet Clearing",
		"The trees part on a patch of soft grass and sunlight. It would be a good place to catch your breath.",
		[&"forest"], [
			_choice("Rest for a while", "You sit in the grass until your legs stop aching.", [heal]),
			_choice("Keep going", "Better not to linger.", []),
		])


func _adventurer() -> EventData:
	return _event(&"adventurer", "A Fellow Traveler",
		"A lone adventurer sits by a small fire, polishing a worn blade. He looks up and gestures at the empty log next to him.",
		[], [
			_choice("Share a meal and swap stories", "He tells of a collapsed bridge, a talking raven and a debt he never paid. You trade tales of your own and part as friends.", []),
			_choice("Nod and move on", "He shrugs and goes back to his blade.", []),
		])


func _sarcophagus() -> EventData:
	var gain := EventGainLoot.new()
	gain.loot = _loot({&"stone": 3})
	var hurt := EventDamageParty.new()
	hurt.amount = 5
	return _event(&"sarcophagus", "The Sealed Sarcophagus",
		"A stone coffin lies in an alcove, its lid carved with a warning nobody can read anymore. Fine blocks of worked stone surround it.",
		[&"catacomb"], [
			_choice("Pry it open", "The lid gives way in a shower of dust and splinters. You salvage what you can and cough your way out.", [gain, hurt]),
			_choice("Leave it sealed", "Some warnings are worth heeding.", []),
		])


# ---------------------------------------------------------------------------
# Helpers (typed arrays and dictionaries cannot be built from plain literals)
# ---------------------------------------------------------------------------

func _event(id: StringName, title: String, text: String, tags: Array, choices: Array) -> EventData:
	var event := EventData.new()
	event.id = id
	event.title = title
	event.text = text
	event.tags.assign(tags)
	event.choices.assign(choices)
	return event


func _choice(label: String, result_text: String, effects: Array) -> EventChoice:
	var choice := EventChoice.new()
	choice.label = label
	choice.result_text = result_text
	choice.effects.assign(effects)
	return choice


func _loot(values: Dictionary) -> Dictionary[StringName, int]:
	var loot: Dictionary[StringName, int] = {}
	for id in values:
		loot[id] = values[id]
	return loot


## Removes the old file, saves, and reads the resource back so the catalog references the file.
func _save(resource: Resource, path: String) -> Resource:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var error := ResourceSaver.save(resource, path)
	if error != OK:
		push_error("make_events: could not save %s (error %d)." % [path, error])
		return null
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
