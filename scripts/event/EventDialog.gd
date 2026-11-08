class_name EventDialog
extends Control
## The window of an event: title, picture, text and one button per choice, then the result
## with a Continue button. Built entirely in code (no scene to assemble): the expedition
## screen adds it as its last child, so it covers the map and blocks its clicks.
##
## It only shows things. The expedition screen applies the choice (signal `choice_selected`)
## and then calls `show_result`.

signal choice_selected(choice: EventChoice)
signal finished  ## Continue pressed; the dialog frees itself right after.

const PANEL_WIDTH := 520.0
const MARGIN := 18

var _title_label: Label
var _art: TextureRect
var _body_label: Label
var _choices_box: VBoxContainer


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # nothing below the dialog can be clicked

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, MARGIN)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 22)
	box.add_child(_title_label)

	_art = TextureRect.new()
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # keep pixel art sharp
	_art.custom_minimum_size = Vector2(0.0, 96.0)
	_art.hide()
	box.add_child(_art)

	_body_label = Label.new()
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.custom_minimum_size = Vector2(PANEL_WIDTH - 2.0 * MARGIN, 0.0)
	box.add_child(_body_label)

	_choices_box = VBoxContainer.new()
	_choices_box.add_theme_constant_override("separation", 8)
	box.add_child(_choices_box)


## Shows the event and its choices. Call it once the dialog is in the tree.
func show_event(event: EventData, run: RunState) -> void:
	_title_label.text = event.title
	_body_label.text = event.text
	_art.texture = event.art
	_art.visible = event.art != null

	_clear_choices()
	for choice in event.choices:
		if choice == null:
			continue
		var button := Button.new()
		var text := choice.label
		var preview := choice.get_preview()
		if preview != "":
			text += "\n" + preview
		var reason := choice.get_blocked_reason(run)
		if reason != "":
			text += "\n(%s)" % reason
			button.disabled = true
		button.text = text
		button.pressed.connect(_on_choice_pressed.bind(choice))
		_choices_box.add_child(button)
	_focus_first_button.call_deferred()


## Replaces the choices with what happened and a Continue button.
func show_result(result_text: String, lines: PackedStringArray) -> void:
	var parts: PackedStringArray = []
	if result_text != "":
		parts.append(result_text)
	if not lines.is_empty():
		parts.append("\n".join(lines))
	_body_label.text = "\n\n".join(parts)

	_clear_choices()
	var button := Button.new()
	button.text = "Continue"
	button.pressed.connect(_on_continue_pressed)
	_choices_box.add_child(button)
	_focus_first_button.call_deferred()


func _on_choice_pressed(choice: EventChoice) -> void:
	for button in _choices_box.get_children():
		(button as Button).disabled = true  # no double click while the result is prepared
	choice_selected.emit(choice)


func _on_continue_pressed() -> void:
	finished.emit()
	queue_free()


func _clear_choices() -> void:
	for child in _choices_box.get_children():
		_choices_box.remove_child(child)
		child.queue_free()


func _focus_first_button() -> void:
	for child in _choices_box.get_children():
		var button := child as Button
		if button != null and not button.disabled:
			button.grab_focus()
			return
