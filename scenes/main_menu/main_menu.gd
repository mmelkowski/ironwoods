extends Control
## The main menu.
##   New game  asks for a name and creates a new save file, then goes to the hub.
##   Continue  loads the most recently saved game.
##   Load      shows every saved game (name and date of its last save) as a row;
##             choosing one loads it. From then on, all saves go into that file.
## A save made in the middle of an expedition resumes on the expedition map,
## otherwise the game opens in the hub.
##
## Nodes with "Access as Unique Name": NewGameButton, ContinueButton, LoadButton,
## QuitButton, SavePanel (hidden at start) and SaveList (a VBoxContainer inside
## SavePanel, ideally within a ScrollContainer). Optional: a Label named
## MessageLabel shows why a save couldn't be loaded.

@onready var new_game_button: Button = %NewGameButton
@onready var continue_button: Button = %ContinueButton
@onready var load_button: Button = %LoadButton
@onready var quit_button: Button = %QuitButton
@onready var save_panel: Control = %SavePanel
@onready var save_list: Container = %SaveList
@onready var message_label: Label = get_node_or_null("%MessageLabel")

var _name_dialog: ConfirmationDialog
var _name_edit: LineEdit


func _ready() -> void:
	new_game_button.pressed.connect(_on_new_game_pressed)
	continue_button.pressed.connect(_on_continue_pressed)
	load_button.pressed.connect(_on_load_pressed)
	quit_button.pressed.connect(get_tree().quit)
	_build_name_dialog()

	var has_save := GameState.has_save()
	continue_button.disabled = not has_save
	load_button.disabled = GameState.list_saves().is_empty()
	quit_button.visible = not OS.has_feature("web")  # a web page can't quit
	save_panel.hide()
	if message_label != null:
		message_label.text = ""

	# So the menu can be used with the keyboard or a gamepad
	if has_save:
		continue_button.grab_focus()
	else:
		new_game_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if save_panel.visible and event.is_action_pressed("ui_cancel"):
		save_panel.hide()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# New game
# ---------------------------------------------------------------------------

## The window that asks for the name of the new save.
func _build_name_dialog() -> void:
	_name_dialog = ConfirmationDialog.new()
	_name_dialog.title = "New game"
	_name_dialog.ok_button_text = "Start"

	var box := VBoxContainer.new()
	var prompt := Label.new()
	prompt.text = "Name of your saved game:"
	_name_edit = LineEdit.new()
	_name_edit.max_length = 24
	_name_edit.placeholder_text = "New game"
	box.add_child(prompt)
	box.add_child(_name_edit)
	_name_dialog.add_child(box)

	_name_dialog.register_text_enter(_name_edit)  # Enter validates
	_name_dialog.confirmed.connect(_on_name_confirmed)
	add_child(_name_dialog)


func _on_new_game_pressed() -> void:
	_name_edit.text = ""
	_name_dialog.popup_centered(Vector2i(380, 140))
	_name_edit.grab_focus()


func _on_name_confirmed() -> void:
	GameState.new_game(_name_edit.text)
	SceneManager.go_to(&"hub")


# ---------------------------------------------------------------------------
# Continue / Load
# ---------------------------------------------------------------------------

func _on_continue_pressed() -> void:
	_load_slot(GameState.latest_save_slot())


func _on_load_pressed() -> void:
	if save_panel.visible:
		save_panel.hide()
		return
	_fill_save_list()
	save_panel.show()


## One row per saved game: its name (a button that loads it) and the date of its last save.
func _fill_save_list() -> void:
	for child in save_list.get_children():
		save_list.remove_child(child)
		child.queue_free()

	var saves := GameState.list_saves()
	if saves.is_empty():
		var none := Label.new()
		none.text = "No saved games."
		save_list.add_child(none)
		return

	for entry in saves:
		var row := HBoxContainer.new()

		var name_button := Button.new()
		name_button.text = entry["name"] if entry["ok"] else "Damaged save (%s)" % entry["id"]
		name_button.disabled = not entry["ok"]
		name_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_button.pressed.connect(_load_slot.bind(entry["id"]))
		row.add_child(name_button)

		var date_label := Label.new()
		date_label.text = _format_date(entry["saved_at"])
		row.add_child(date_label)

		var del_save_button := Button.new()
		del_save_button.text = "Delete file"
		del_save_button.pressed.connect(_del_savefile.bind(entry["id"]))
		row.add_child(del_save_button)

		save_list.add_child(row)


func _load_slot(slot_id: String) -> void:
	if GameState.load_game(slot_id):
		# A save made in the middle of an expedition resumes on its map
		SceneManager.go_to(&"expedition" if GameState.has_run() else &"hub")
	elif message_label != null:
		message_label.text = "The save could not be loaded: %s." % GameState.load_error


func _del_savefile(slot_id: String) -> void:
	SaveManager.delete(slot_id)
	# refresh save file list
	_fill_save_list()


## "2025-10-18 14:32", in the player's local time.
func _format_date(unix_time: float) -> String:
	if unix_time <= 0.0:
		return ""
	var bias_minutes := int(Time.get_time_zone_from_system()["bias"])
	var local_time := int(unix_time) + bias_minutes * 60
	return Time.get_datetime_string_from_unix_time(local_time, true).left(16)
