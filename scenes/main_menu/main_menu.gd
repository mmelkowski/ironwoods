extends Control
## The main menu: start a new game or continue a saved one.
## New game creates a fresh profile (the starting heroes) and goes to the hub.
## Continue is disabled until there is a save file.
##
## The three buttons use "Access as Unique Name".

@onready var new_game_button: Button = %NewGameButton
@onready var continue_button: Button = %ContinueButton
@onready var quit_button: Button = %QuitButton


func _ready() -> void:
	new_game_button.pressed.connect(_on_new_game_pressed)
	continue_button.pressed.connect(_on_continue_pressed)
	quit_button.pressed.connect(get_tree().quit)

	var has_save := GameState.has_save()
	continue_button.disabled = not has_save
	quit_button.visible = not OS.has_feature("web")  # a web page can't quit

	# So the menu can be used with the keyboard or a gamepad
	if has_save:
		continue_button.grab_focus()
	else:
		new_game_button.grab_focus()


func _on_new_game_pressed() -> void:
	# TODO (phase 6): ask for confirmation when a save exists, since it will be overwritten
	GameState.new_game()
	SceneManager.go_to(&"hub")


func _on_continue_pressed() -> void:
	if not GameState.load_game():
		return
	# A save made in the middle of an expedition resumes on its map
	SceneManager.go_to(&"expedition" if GameState.has_run() else &"hub")
