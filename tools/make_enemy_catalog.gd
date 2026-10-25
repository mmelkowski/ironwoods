@tool
extends EditorScript
## File > Run (Ctrl+Shift+X) with this script open.
## Builds res://data/enemy_catalog.tres from every enemy .tres found in ENEMIES_DIR
## (only CharacterData on the ENEMY team). Re-run it after adding an enemy: it overwrites the catalog.

const ENEMIES_DIR := "res://data/character/enemies"
const OUTPUT := "res://data/enemy_catalog.tres"


func _run() -> void:
	var dir := DirAccess.open(ENEMIES_DIR)
	if dir == null:
		push_error("make_enemy_catalog: can't open %s" % ENEMIES_DIR)
		return

	var files: Array[String] = []
	for file in dir.get_files():
		if file.ends_with(".tres"):
			files.append(file)
	files.sort()

	var catalog := EnemyCatalog.new()
	for file in files:
		var data := load(ENEMIES_DIR.path_join(file)) as CharacterData
		if data != null and data.team == CharacterData.Team.ENEMY:
			catalog.enemies.append(data)

	var error := ResourceSaver.save(catalog, OUTPUT)
	if error != OK:
		push_error("make_enemy_catalog: couldn't save %s (error %d)" % [OUTPUT, error])
		return
	EditorInterface.get_resource_filesystem().scan()
	print("make_enemy_catalog: %d enemies written to %s" % [catalog.enemies.size(), OUTPUT])
	catalog.validate()
