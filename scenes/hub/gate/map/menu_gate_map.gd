extends HubMenu

var selected_expedition_id: StringName = &""
var currently_selected_site: ExpeditionSite = null

@onready var title_label: Label = %TitleLabel
@onready var body_label: Label = %BodyLabel
@onready var status_label: Label = %StatusLabel
@onready var choose_team_button: Button = %ChooseTeamButton
@onready var Expedition_Site_Nodes = $ExpeditionSiteNodes
# Preload your menu_gate scene (adjust the path if your file is located elsewhere)
const MENU_GATE_SCENE = preload("res://scenes/hub/gate/menu_gate.tscn")

func _ready() -> void:
	super._ready()  # keeps the close button working
	# Connect expedition sites: each one holds its own expedition (its `expedition` export)
	for child in Expedition_Site_Nodes.get_children():
		var site := child as ExpeditionSite
		if site == null:
			push_warning("menu_gate_map: '%s' is not an ExpeditionSite, ignored." % child.name)
			continue
		if site.expedition == null:
			push_warning("menu_gate_map: the site '%s' has no expedition assigned, it is hidden." % site.name)
			site.visible = false
			site.input_pickable = false
			continue
		_check_registered(site)
		site.configure(site.expedition, _state_of(site.expedition),
			GameState.profile.is_expedition_completed(site.expedition.id))
		site.selected.connect(_on_expedition_site_selected)

	# Connect the Choose Team button
	choose_team_button.pressed.connect(_on_choose_team_pressed)
	
	# Initially disable the button until a site is selected
	choose_team_button.disabled = true

func _on_expedition_site_selected(site: ExpeditionSite) -> void:
	if currently_selected_site and is_instance_valid(currently_selected_site):
		currently_selected_site.set_selected(false)
	
	currently_selected_site = site
	currently_selected_site.set_selected(true)
	
	# A locked (teased) site can be selected to read how to unlock it, but not launched
	var launchable := site.state == ExpeditionSite.State.UNLOCKED
	selected_expedition_id = site.expedition_id if launchable else &""
	choose_team_button.disabled = not launchable

	_update_ui(site)

func _update_ui(site: ExpeditionSite) -> void:
	if site.state == ExpeditionSite.State.TEASED:
		title_label.text = "???"
		body_label.text = GameState.get_expedition_unlock_text(site.expedition)
		status_label.text = "Locked"
		return
	if site.expedition:
		#title_label.text = site.expedition_id
		title_label.text = site.expedition.display_name
		body_label.text = site.expedition.description if "description" in site.expedition else "Target location selected."
	else:
		title_label.text = String(site.expedition_id).capitalize()
		body_label.text = "Expedition site selected."
	status_label.text = "ID: " + String(site.expedition_id)

## How the site looks: UNLOCKED (normal), TEASED (black silhouette, "???" and the unlock hint) or
## HIDDEN (not shown), from the unlock conditions of the expedition.
func _state_of(expedition: ExpeditionData) -> ExpeditionSite.State:
	match GameState.get_expedition_access(expedition):
		GameState.Access.UNLOCKED:
			return ExpeditionSite.State.UNLOCKED
		GameState.Access.TEASED:
			return ExpeditionSite.State.TEASED
	return ExpeditionSite.State.HIDDEN


## A run is started and saved by id and looked up in the expedition catalog, so an expedition
## that is only on a site (and not in data/expedition_catalog.tres) cannot be launched.
func _check_registered(site: ExpeditionSite) -> void:
	var registered := GameState.expeditions.get_expedition(site.expedition.id)
	if registered == null:
		push_warning("menu_gate_map: the site '%s' uses '%s', which is not in the expedition catalog: it cannot be launched. Add it to data/expedition_catalog.tres." % [site.name, site.expedition.id])
	elif registered.resource_path != site.expedition.resource_path:
		push_warning("menu_gate_map: the site '%s' uses %s but the catalog holds %s for the id '%s': the run will use the catalog's." % [
			site.name, site.expedition.resource_path, registered.resource_path, site.expedition.id])


func _on_choose_team_pressed() -> void:
	# Double check that an expedition ID is actually selected
	if selected_expedition_id.is_empty():
		return
	if GameState.expeditions.get_expedition(selected_expedition_id) == null:
		push_error("menu_gate_map: '%s' is not in the expedition catalog, a run cannot start without it. Add it to data/expedition_catalog.tres." % selected_expedition_id)
		return
	# Instantiate the menu_gate scene
	var menu_gate_instance = MENU_GATE_SCENE.instantiate()
	# Pass the selected expedition ID before adding it to the scene tree,
	# ensuring it's available when menu_gate's _ready() executes.
	menu_gate_instance.expedition_id = selected_expedition_id
	menu_gate_instance.closed.connect(_on_gate_closed.bind(menu_gate_instance))
	# Add it to the UI layer or root node so it displays on screen
	# (Using %UI or adding to self/get_tree().root depending on your project structure)
	%UI.add_child(menu_gate_instance)

func _on_gate_closed(gate: Node) -> void:
	if is_instance_valid(gate):
		gate.queue_free()
