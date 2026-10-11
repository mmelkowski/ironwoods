class_name HubMenu
extends Control
## Base class of every hub menu (team selection, tavern, forge...).
##
## To make a menu: create a scene whose root is a Control with a script that
## extends HubMenu, and assign that scene to a HubLocation's `menu_scene`.
## Tips for the scene:
##   - make the root fill the screen with Mouse Filter = Stop (so the town
##     behind can't be clicked); a dark ColorRect makes a nice backdrop,
##   - assign `close_button` if the menu has a Close / Back button.
##
## When the menu is done it calls close(): the Hub removes it and gives the town
## back to the player. Esc closes it too. If you override _ready(), call super._ready().

signal closed

## Optional: a button that closes the menu.
@export var close_button: Button


func _ready() -> void:
	if close_button != null:
		close_button.pressed.connect(close)


## Closes the menu (the Hub frees it).
func close() -> void:
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
