class_name HeroPortrait
extends Button
## One hero in the selection grid: his head, and a number once he is in the team.
##
## Scene (hero_portrait.tscn):
##   HeroPortrait (Button, this script, a custom_minimum_size around 64x64)
##   └── Badge (Label, "Access as Unique Name", top-left corner, hidden)
## The Button's "Pressed" style is the look of a selected hero (a bright border, for instance).

## Size of the cut taken around the head, in sprite pixels.
const HEAD_CROP := Vector2(16, 16)

@onready var badge: Label = %Badge

var hero: CharacterData


func setup(data: CharacterData) -> void:
	hero = data
	icon = data.get_head_texture(HEAD_CROP)
	expand_icon = true  # the icon fills the button
	toggle_mode = true  # the pressed style marks the selected heroes
	tooltip_text = data.display_name


## 1 to 3 = position in the team, 0 = not picked.
func set_pick_number(number: int) -> void:
	set_pressed_no_signal(number > 0)
	badge.visible = number > 0
	badge.text = str(number)
