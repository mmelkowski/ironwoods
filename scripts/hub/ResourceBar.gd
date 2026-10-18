class_name ResourceBar
extends HBoxContainer
## Shows the player's stock of resources ("Wood 12   Stone 5"), updated as it changes.
## Attach it to an HBoxContainer in the hub HUD (or any menu). Only the resources
## the player owns are listed.

func _ready() -> void:
	_rebuild()
	GameState.profile.resources_changed.connect(_rebuild)


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	var ids := GameState.profile.resources.keys()
	ids.sort()
	for id in ids:
		var amount := GameState.profile.get_resource(id)
		if amount <= 0:
			continue
		var label := Label.new()
		label.text = "%s %d" % [String(id).capitalize(), amount]
		add_child(label)


## { &"wood": 10, &"stone": 5 } -> "Wood 10, Stone 5" ("Free" for an empty cost).
static func describe(resources: Dictionary) -> String:
	if resources.is_empty():
		return "Free"
	var parts: PackedStringArray = []
	for id in resources:
		parts.append("%s %d" % [String(id).capitalize(), resources[id]])
	return ", ".join(parts)
