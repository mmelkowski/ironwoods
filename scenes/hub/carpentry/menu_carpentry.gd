extends HubMenu
## The carpentry workshop: spend resources to build and upgrade the buildings of the
## hub. A built building appears in the hub at its fixed position.
##
## Scene: a Control (this script) with a close button and a VBoxContainer named
## BuildingList ("Access as Unique Name") where the rows are built. Optional: a
## ResourceBar to show the stock while shopping.

@onready var building_list: Container = %BuildingList


func _ready() -> void:
	super._ready()  # keeps the close button working
	_fill_list()


## One row per building. Buildings whose requirements are not met yet stay hidden.
func _fill_list() -> void:
	for child in building_list.get_children():
		building_list.remove_child(child)
		child.queue_free()

	for building in GameState.buildings.buildings:
		if GameState.are_requirements_met(building):
			building_list.add_child(_make_row(building))


func _make_row(building: BuildingData) -> Control:
	var level := GameState.get_building_level(building.id)
	var next := GameState.get_next_building_level(building)

	var row := HBoxContainer.new()

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := Label.new()
	title.text = building.display_name
	title.text += " (level %d)" % level if level > 0 else " (not built)"
	info.add_child(title)
	var detail := Label.new()
	detail.text = next.description if next != null else "Maximum level."
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(detail)
	row.add_child(info)

	if next != null:
		var cost := Label.new()
		cost.text = ResourceBar.describe(next.cost)
		row.add_child(cost)

		var button := Button.new()
		button.text = "Build" if level == 0 else "Upgrade"
		button.disabled = not GameState.can_upgrade_building(building)
		button.pressed.connect(_on_upgrade_pressed.bind(building))
		row.add_child(button)
	return row


func _on_upgrade_pressed(building: BuildingData) -> void:
	if GameState.upgrade_building(building):
		_fill_list()  # new levels, new costs, and maybe newly available buildings
