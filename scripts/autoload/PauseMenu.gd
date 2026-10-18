extends CanvasLayer
## AUTOLOAD (Project Settings > Globals > Autoload, name: PauseMenu, pointing at the
## scene that uses this script). Don't give this script a class_name.
##
## The pause menu: Esc opens it anywhere except the main menu (hub, expedition,
## battle) and pauses the game. Esc again, or Resume, closes it.
##   Save       saves the game now (not available during a battle).
##   Main menu  goes back to the main menu, after a yes/no prompt.
##   Quit       quits to the desktop, after a yes/no prompt.
##
## Scene (pause_menu.tscn):
##   PauseMenu (CanvasLayer, this script)
##   └── Root (Control, full rect, Mouse Filter = Stop so the game behind can't be clicked)
##       ├── Dim (ColorRect, full rect, black with some transparency)
##       └── CenterContainer (full rect)
##           └── PanelContainer
##               └── VBoxContainer
##                   ├── TitleLabel  (Label, text "Pause")
##                   ├── ResumeButton    (optional)
##                   ├── SaveButton
##                   ├── MainMenuButton
##                   └── QuitButton
## The four buttons use "Access as Unique Name".

@onready var save_button: Button = %SaveButton
@onready var main_menu_button: Button = %MainMenuButton
@onready var quit_button: Button = %QuitButton
@onready var resume_button: Button = get_node_or_null("%ResumeButton")

var _confirm_dialog: AcceptDialog
var _confirm_label: Label
var _on_yes: Callable


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # keeps working while the game is paused
	layer = 50
	hide()

	save_button.pressed.connect(_on_save_pressed)
	main_menu_button.pressed.connect(_ask.bind(
		"Go back to the main menu?\nProgress since your last save will be lost.", _go_to_main_menu))
	quit_button.pressed.connect(_ask.bind(
		"Quit to the desktop?\nProgress since your last save will be lost.", get_tree().quit))
	if resume_button != null:
		resume_button.pressed.connect(close)
	quit_button.visible = not OS.has_feature("web")  # a web page can't quit

	_build_confirm_dialog()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if visible:
		close()
	elif _can_open():
		open()
	else:
		return  # not our business: let other scripts use the key
	get_viewport().set_input_as_handled()


func open() -> void:
	var in_battle := _in_battle()
	save_button.text = "Save"
	save_button.disabled = in_battle  # a battle is never saved in the middle
	save_button.tooltip_text = "You can't save during a battle." if in_battle else ""
	show()
	get_tree().paused = true

	# So the menu can be used with the keyboard or a gamepad
	var first: Button = resume_button if resume_button != null else main_menu_button
	first.grab_focus()


func close() -> void:
	_confirm_dialog.hide()
	hide()
	get_tree().paused = false


## Not in the main menu, not while changing scene, not if something else paused the game.
func _can_open() -> bool:
	var scene := get_tree().current_scene
	if scene.name == "MainMenu":
		return false
	elif scene == null or SceneManager.is_changing() or get_tree().paused:
		return false
	return scene.scene_file_path != SceneManager.ROUTES[&"main_menu"]


func _in_battle() -> bool:
	var scene := get_tree().current_scene
	return scene != null and scene.scene_file_path == SceneManager.ROUTES[&"battle"]


func _on_save_pressed() -> void:
	if GameState.save_game():
		save_button.text = "Saved!"
	else:
		save_button.text = "Nothing to save"  # no game in progress (a scene run on its own)
	await get_tree().create_timer(1.5).timeout  # keeps running while paused
	save_button.text = "Save"


func _go_to_main_menu() -> void:
	close()  # unpauses first, so the scene change can run
	SceneManager.go_to(&"main_menu")


# ---------------------------------------------------------------------------
# Yes / no prompt
# ---------------------------------------------------------------------------

func _build_confirm_dialog() -> void:
	_confirm_dialog = AcceptDialog.new()
	_confirm_dialog.title = "Are you sure?"
	_confirm_dialog.get_ok_button().hide()  # replaced by the two buttons below

	var box := VBoxContainer.new()
	_confirm_label = Label.new()
	_confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_label.custom_minimum_size.x = 340.0
	box.add_child(_confirm_label)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	var no_button := Button.new()
	no_button.text = "No"
	no_button.pressed.connect(_confirm_dialog.hide)
	buttons.add_child(no_button)
	var yes_button := Button.new()
	yes_button.text = "Yes"
	yes_button.pressed.connect(_on_confirmed)
	buttons.add_child(yes_button)
	box.add_child(buttons)

	_confirm_dialog.add_child(box)
	add_child(_confirm_dialog)


func _ask(message: String, on_yes: Callable) -> void:
	_on_yes = on_yes
	_confirm_label.text = message
	_confirm_dialog.popup_centered(Vector2i(400, 160))


func _on_confirmed() -> void:
	_confirm_dialog.hide()
	var action := _on_yes
	_on_yes = Callable()
	if action.is_valid():
		action.call()
