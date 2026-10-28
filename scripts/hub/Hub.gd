class_name Hub
extends Node2D
## The town: the screen where the player clicks on places to open menus.
##
## Scene: Hub (Node2D, this script)
##        ├── TileMapLayer / decor
##        └── HubLocation nodes (gate, tavern, forge...) anywhere below it
##
## Adding a place = adding a HubLocation at its FIXED position, filling its id, name
## and menu_scene, and adding the matching BuildingData to the building catalog.
## The Hub finds every HubLocation below it by itself, nothing to register.
##
## A place is hidden until the player has unlocked it (new games start with the
## buildings marked built_at_start); it appears as soon as the carpentry workshop
## builds it. The hub is saved each time it opens.

## A place was clicked (fires even if it has no menu: handle special places here).
signal location_activated(location: HubLocation)
signal menu_opened(location: HubLocation)
signal menu_closed(location: HubLocation)

var _locations: Array[HubLocation] = []
var _menu_layer: CanvasLayer
var _menu: HubMenu
var _menu_location: HubLocation


func _ready() -> void:
	# Menus live on their own layer so they are drawn above the town
	_menu_layer = CanvasLayer.new()
	_menu_layer.layer = 2
	add_child(_menu_layer)

	for node in get_tree().get_nodes_in_group(HubLocation.GROUP):
		if is_ancestor_of(node):
			var location := node as HubLocation
			_locations.append(location)
			location.activated.connect(_on_location_activated)

	_check_scene()
	_apply_unlocks()
	GameState.profile.locations_changed.connect(_apply_unlocks)
	GameState.save_game()  # autosave whenever the hub opens


## Shows the places the player has unlocked and hides the others.
func _apply_unlocks() -> void:
	for location in _locations:
		location.set_unlocked(GameState.profile.is_location_unlocked(location.location_id))


## Authoring check: every place needs a building in the catalog and the other way round.
func _check_scene() -> void:
	var placed := {}
	for location in _locations:
		placed[location.location_id] = true
		if not location.always_unlocked and GameState.buildings.get_building(location.location_id) == null:
			push_warning("Hub: '%s' is not in the building catalog, it will stay hidden." % location.location_id)
	for building in GameState.buildings.buildings:
		if not placed.has(building.id):
			push_warning("Hub: the building '%s' has no HubLocation in this scene." % building.id)


func is_menu_open() -> bool:
	return _menu != null


## Opens the menu of a location. Does nothing if a menu is already open.
func open_menu(location: HubLocation) -> void:
	if _menu != null or location.menu_scene == null:
		return

	var menu := location.menu_scene.instantiate() as HubMenu
	if menu == null:
		push_error("Hub: the menu of '%s' must have a root extending HubMenu." % location.location_id)
		return

	_menu = menu
	_menu_location = location
	menu.closed.connect(_close_menu)
	_menu_layer.add_child(menu)
	_set_locations_interactive(false)
	menu_opened.emit(location)


func _on_location_activated(location: HubLocation) -> void:
	if _menu != null:
		return
	location_activated.emit(location)
	if location.route != &"":  # a place that leads to another scene (the gate -> the world map)
		SceneManager.go_to(location.route)
		return
	open_menu(location)


func _close_menu() -> void:
	if _menu == null:
		return
	var location := _menu_location
	_menu.queue_free()
	_menu = null
	_menu_location = null
	_set_locations_interactive(true)
	menu_closed.emit(location)


func _set_locations_interactive(interactive: bool) -> void:
	for location in _locations:
		location.set_interactive(interactive)
