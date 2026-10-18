class_name SaveUtils
extends RefCounted
## Small helpers to turn game data into what JSON can store, and back.
## JSON has no StringName and gives every number back as a float, so ids are saved
## as strings and converted again when loading, and whole numbers become ints again.


## [&"a", &"b"] -> ["a", "b"]
static func to_strings(names: Array) -> Array:
	var result := []
	for item in names:
		result.append(String(item))
	return result


## ["a", "b"] -> [&"a", &"b"]. Anything that isn't an array gives an empty array.
static func to_names(strings: Variant) -> Array[StringName]:
	var result: Array[StringName] = []
	if strings is Array:
		for item in strings:
			result.append(StringName(item))
	return result


## { &"wood": 3 } -> { "wood": 3 }
static func dict_to_json(source: Dictionary) -> Dictionary:
	var result := {}
	for key in source:
		result[String(key)] = source[key]
	return result


## { "wood": 3.0 } -> { &"wood": 3 }. For dictionaries whose values are whole numbers
## (resources, health, upgrade levels, loot). Anything that isn't a dictionary gives {}.
static func int_dict_from_json(source: Variant) -> Dictionary:
	var result := {}
	if source is Dictionary:
		for key in source:
			result[StringName(key)] = int(source[key])
	return result
