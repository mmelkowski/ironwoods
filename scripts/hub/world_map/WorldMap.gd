class_name WorldMap
extends Node2D
## The scene where the player chooses an expedition (route "world_map"), between the hub's gate
## and the team selection.
##
## Scene tree (unique names, "Access as Unique Name"):
##   WorldMap (this script)
##   ├── Background (Sprite2D or whatever you like)
##   ├── ExpeditionSite ... (one instance of expedition_site.tscn per expedition)
##   ├── UI (CanvasLayer)
##   │   ├── %InfoPanel (PanelContainer) > VBox > %TitleLabel, %BodyLabel, %StatusLabel, %ChooseTeamButton
##   │   ├── %BackButton
##   │   └── (optional) ResourceBar
##   └── %MenuLayer (CanvasLayer, layer above UI): the team selection menu is added here
##
## Each site is shown according to GameState.get_expedition_access: unlocked, teased or hidden.

## The team selection menu (the existing gate menu, menu_gate.tscn). It must have an
## `expedition_id` variable: it is set before the menu enters the tree.
@export var team_menu_scene: PackedScene
## Where the Back button goes.
@export var back_route: StringName = &"hub"

@onready var info_panel: Control = %InfoPanel
@onready var title_label: Label = %TitleLabel
@onready var body_label: Label = %BodyLabel
@onready var status_label: Label = %StatusLabel
@onready var choose_team_button: Button = %ChooseTeamButton
@onready var back_button: Button = %BackButton
@onready var menu_layer: CanvasLayer = %MenuLayer

var _sites: Array[ExpeditionSite] = []
var _selected: ExpeditionSite
var _menu: Node  # the team selection while it is open


func _ready() -> void:
	for node in get_tree().get_nodes_in_group(&"expedition_sites"):
		var site := node as ExpeditionSite
		if site != null:
			_sites.append(site)
			site.selected.connect(_on_site_selected)

	choose_team_button.pressed.connect(_on_choose_team_pressed)
	back_button.pressed.connect(_on_back_pressed)

	_refresh_sites()
	_show_info(null)
	_check_scene()


## Applies the unlock state of every expedition to its site.
func _refresh_sites() -> void:
	for site in _sites:
		var expedition := GameState.expeditions.get_expedition(site.expedition_id)
		if expedition == null:
			site.visible = false  # unknown id: _check_scene reports it
			site.input_pickable = false
			continue
		var state := ExpeditionSite.State.HIDDEN
		var access := GameState.get_expedition_access(expedition)
		if access == GameState.Access.UNLOCKED:
			state = ExpeditionSite.State.UNLOCKED
		elif access == GameState.Access.TEASED:
			state = ExpeditionSite.State.TEASED
		site.configure(expedition, state, GameState.profile.is_expedition_completed(expedition.id))


func _on_site_selected(site: ExpeditionSite) -> void:
	if _menu != null:
		return
	if _selected != null:
		_selected.set_selected(false)
	_selected = site
	_selected.set_selected(true)
	_show_info(site)


## Fills the panel for a site (null hides the panel).
func _show_info(site: ExpeditionSite) -> void:
	if site == null:
		info_panel.hide()
		return
	info_panel.show()
	var expedition := site.expedition

	if site.state == ExpeditionSite.State.TEASED:
		title_label.text = "???"
		body_label.text = GameState.get_expedition_unlock_text(expedition)
		status_label.text = "Locked"
		choose_team_button.hide()
		return

	title_label.text = expedition.display_name
	var lines: Array[String] = []
	if expedition.description != "":
		lines.append(expedition.description)
	if expedition.goal != "":
		lines.append("Goal: %s" % expedition.goal)
	if not expedition.completion_bonus.is_empty():
		lines.append("Reward: %s" % ResourceBar.describe(expedition.completion_bonus))
	body_label.text = "\n\n".join(lines)
	status_label.text = "Completed" if GameState.profile.is_expedition_completed(expedition.id) else ""
	choose_team_button.show()


## "Choose team": opens the team selection for the selected expedition.
func _on_choose_team_pressed() -> void:
	if _menu != null or _selected == null or _selected.state != ExpeditionSite.State.UNLOCKED:
		return
	if team_menu_scene == null:
		push_error("WorldMap: assign team_menu_scene (menu_gate.tscn) in the inspector.")
		return

	_menu = team_menu_scene.instantiate()
	if "expedition_id" in _menu:
		_menu.set(&"expedition_id", _selected.expedition.id)
	else:
		push_warning("WorldMap: the team menu has no `expedition_id` variable, it will not know which expedition was chosen.")
	if _menu.has_signal(&"closed"):
		_menu.connect(&"closed", _on_menu_closed)
	_menu.tree_exited.connect(_on_menu_closed)
	menu_layer.add_child(_menu)
	_set_interactive(false)


func _on_menu_closed(_a = null, _b = null) -> void:
	if _menu == null:
		return
	var menu := _menu
	_menu = null
	if is_instance_valid(menu) and menu.is_inside_tree():
		menu.queue_free()
	if is_inside_tree():
		_set_interactive(true)


func _set_interactive(value: bool) -> void:
	for site in _sites:
		if is_instance_valid(site):
			site.set_interactive(value)
	choose_team_button.disabled = not value
	back_button.disabled = not value


func _on_back_pressed() -> void:
	if _menu == null:
		SceneManager.go_to(back_route)


## Warns in the Output about a site without a matching expedition, or an expedition without a site.
func _check_scene() -> void:
	var placed := {}
	for site in _sites:
		if site.expedition_id == &"":
			push_warning("WorldMap: the site '%s' has no expedition_id." % site.name)
		elif GameState.expeditions.get_expedition(site.expedition_id) == null:
			push_warning("WorldMap: the site '%s' uses an unknown expedition '%s'." % [site.name, site.expedition_id])
		else:
			placed[site.expedition_id] = true
	for expedition in GameState.expeditions.expeditions:
		if not placed.has(expedition.id):
			push_warning("WorldMap: the expedition '%s' has no site on the map." % expedition.id)
