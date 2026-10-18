class_name SaveManager
extends RefCounted
## Reads and writes the save files. It knows nothing about the game, only about
## files: versioned JSON documents, written safely, with a backup. There is one
## file per saved game, so the player can have several.
##
## In the user data folder (Project > Open User Data Folder):
##   saves/<id>.json       a saved game
##   saves/<id>.json.bak   its previous version, used if the file is damaged
##   saves/<id>.json.tmp   only exists while writing

const SAVE_DIR := "user://saves"
const LEGACY_PATH := "user://save.json"  # the single save file of the first version

## Bump it when the format changes, and add a step in _migrate().
const VERSION := 1


static func path_of(slot_id: String) -> String:
	return "%s/%s.json" % [SAVE_DIR, slot_id]


## A file id for a new saved game that doesn't exist yet.
static func new_slot_id() -> String:
	var base := "save_%d" % int(Time.get_unix_time_from_system())
	var id := base
	var counter := 2
	while FileAccess.file_exists(path_of(id)):
		id = "%s_%d" % [base, counter]
		counter += 1
	return id


## Writes `content` into the file of a saved game (the version and the date are
## added). Safe against crashes: the new file is written next to the save and only
## then swapped in, and the old one is kept as a backup.
static func write(slot_id: String, content: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var path := path_of(slot_id)
	var backup_path := path + ".bak"
	var temp_path := path + ".tmp"

	var data := content.duplicate()
	data["version"] = VERSION
	data["saved_at"] = Time.get_unix_time_from_system()

	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: can't write %s (error %d)." % [temp_path, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(data, "\t"))
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		push_error("SaveManager: writing the save failed (error %d)." % write_error)
		DirAccess.remove_absolute(temp_path)
		return false

	# The current file becomes the backup, the new file becomes the save
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(backup_path)
	if FileAccess.file_exists(path):
		DirAccess.rename_absolute(path, backup_path)
	var rename_error := DirAccess.rename_absolute(temp_path, path)
	if rename_error != OK:
		push_error("SaveManager: couldn't put the new save in place (error %d)." % rename_error)
		return false
	return true


## Reads a saved game, falling back to its backup if the file is damaged.
## Returns { "ok": bool, "data": Dictionary, "error": String }.
static func read(slot_id: String, warn: bool = true) -> Dictionary:
	var path := path_of(slot_id)
	var problems: PackedStringArray = []
	for candidate in [path, path + ".bak"]:
		if not FileAccess.file_exists(candidate):
			continue
		var result := _read_file(candidate)
		if result["ok"]:
			if warn and candidate != path:
				push_warning("SaveManager: '%s' was damaged, its backup was loaded instead." % slot_id)
			return result
		problems.append("%s (%s)" % [candidate.get_file(), result["error"]])

	if problems.is_empty():
		return _failure("there is no such save file")
	return _failure("the save file is damaged: " + ", ".join(problems))


## Every saved game, the most recently saved first. Each entry:
## { "id": String, "ok": bool, "name": String, "saved_at": float }
## (`ok` is false for a damaged file that can't be read).
static func list_saves() -> Array[Dictionary]:
	_import_legacy_save()

	var saves: Array[Dictionary] = []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return saves

	# A save whose main file is missing but whose backup exists still counts
	var ids := {}
	for file_name in dir.get_files():
		if file_name.ends_with(".json"):
			ids[file_name.trim_suffix(".json")] = true
		elif file_name.ends_with(".json.bak"):
			ids[file_name.trim_suffix(".json.bak")] = true

	for id in ids:
		var result := read(id, false)
		var entry := {"id": id, "ok": result["ok"], "name": "", "saved_at": 0.0}
		if result["ok"]:
			var data: Dictionary = result["data"]
			entry["name"] = str(data.get("name", "Old save"))
			entry["saved_at"] = float(data.get("saved_at", 0.0))
		saves.append(entry)

	saves.sort_custom(func(a, b): return a["saved_at"] > b["saved_at"])
	return saves


## The id of the most recently saved game that can be loaded ("" if there is none).
static func latest_slot() -> String:
	for entry in list_saves():
		if entry["ok"]:
			return entry["id"]
	return ""


static func delete(slot_id: String) -> void:
	var path := path_of(slot_id)
	for file_path in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(file_path):
			DirAccess.remove_absolute(file_path)


# ---------------------------------------------------------------------------

## The first version had a single save at user://save.json: it becomes a normal
## saved game (named "Old save") the first time the saves are listed.
static func _import_legacy_save() -> void:
	if not FileAccess.file_exists(LEGACY_PATH):
		return
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var path := path_of(new_slot_id())
	DirAccess.rename_absolute(LEGACY_PATH, path)
	if FileAccess.file_exists(LEGACY_PATH + ".bak"):
		DirAccess.rename_absolute(LEGACY_PATH + ".bak", path + ".bak")


static func _read_file(path: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return _failure("invalid JSON: %s" % json.get_error_message())
	if typeof(json.data) != TYPE_DICTIONARY:
		return _failure("not a save file")

	var data: Dictionary = json.data
	if not data.has("version"):
		return _failure("no version number")
	var version := int(data["version"])
	if version > VERSION:
		return _failure("it was made by a newer version of the game")

	return {"ok": true, "data": _migrate(data, version), "error": ""}


## Brings an older save up to the current VERSION. When the format changes, add a
## step here, for example:
##   if version < 2:
##       data = _migrate_1_to_2(data)
static func _migrate(data: Dictionary, _version: int) -> Dictionary:
	data["version"] = VERSION
	return data


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "data": {}, "error": message}
