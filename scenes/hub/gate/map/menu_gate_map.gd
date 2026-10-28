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
	# Connect expedition sites
	for child in Expedition_Site_Nodes.get_children():
		var data := GameState.expeditions.get_expedition(child.expedition_id)
		if data != null:
			child.configure(data, ExpeditionSite.State.UNLOCKED,
				   GameState.profile.is_expedition_completed(child.expedition_id))
		child.selected.connect(_on_expedition_site_selected)
		#if child is ExpeditionSite:
		#	child.selected.connect(_on_expedition_site_selected)
			
	# Connect the Choose Team button
	choose_team_button.pressed.connect(_on_choose_team_pressed)
	
	# Initially disable the button until a site is selected
	choose_team_button.disabled = true

func _on_expedition_site_selected(site: ExpeditionSite) -> void:
	if currently_selected_site and is_instance_valid(currently_selected_site):
		currently_selected_site.set_selected(false)
	
	currently_selected_site = site
	currently_selected_site.set_selected(true)
	
	selected_expedition_id = site.expedition_id

	# Enable the button now that a valid site is chosen
	choose_team_button.disabled = false

	_update_ui(site)

func _update_ui(site: ExpeditionSite) -> void:
	if site.expedition:
		#title_label.text = site.expedition_id
		title_label.text = site.expedition.display_name
		body_label.text = site.expedition.description if "description" in site.expedition else "Target location selected."
	else:
		title_label.text = String(site.expedition_id).capitalize()
		body_label.text = "Expedition site selected."
	status_label.text = "ID: " + String(site.expedition_id)

func _on_choose_team_pressed() -> void:
	# Double check that an expedition ID is actually selected
	if selected_expedition_id.is_empty():
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
