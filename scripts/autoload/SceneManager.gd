extends CanvasLayer
## AUTOLOAD (Project Settings > Globals > Autoload, name: SceneManager).
## Changes scene by route name, with a fade to black. Don't give this script a
## class_name: it would clash with the autoload name.
##
##   SceneManager.go_to(&"hub")
##
## Adjust the paths below to your project.

const ROUTES := {
	&"main_menu": "res://scenes/main_menu/main_menu.tscn",
	&"hub": "res://scenes/hub/hub.tscn",
	&"world_map": "res://scenes/world_map/world_map.tscn",
	&"expedition": "res://scenes/expedition/Expedition.tscn",
	&"battle": "res://scenes/battle/battle.tscn",
}
const FADE_TIME := 0.25

var _fade: ColorRect
var _busy := false


func _ready() -> void:
	layer = 100  # above everything
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.modulate.a = 0.0
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)


## Fades out, loads the scene of the route, fades in.
## Returns false (and does nothing) if the route doesn't exist yet or a change is in progress.
func go_to(route: StringName) -> bool:
	if _busy:
		return false
	var path: String = ROUTES.get(route, "")
	if path == "" or not ResourceLoader.exists(path):
		push_warning("SceneManager: the route '%s' is not available (%s)." % [route, path])
		return false

	_busy = true
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP  # no clicks during the fade
	await _fade_to(1.0)
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame  # the new scene is in place
	await _fade_to(0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false
	return true

## True while a scene change is in progress (the pause menu doesn't open then).
func is_changing() -> bool:
	return _busy


func _fade_to(alpha: float) -> void:
	var tween := create_tween()
	tween.tween_property(_fade, "modulate:a", alpha, FADE_TIME)
	await tween.finished
