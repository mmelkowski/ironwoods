extends HubMenu
## The main gate: pick the team that goes on an expedition.
## Left third: the heroes you own. Right two thirds: the team as it is built.

const TEAM_SIZE := 3
## TODO: the destination will be chosen in this menu. Until then, a fixed expedition.
const DEFAULT_EXPEDITION_ID := &"first_expedition"

@export var hero_portrait_scene: PackedScene   # hero_portrait.tscn
@export var hero_slot_scene: PackedScene       # hero_slot.tscn
## The GridContainer of the left side (columns = 3). Filled by this script.
@export var hero_grid: GridContainer
## The container of the right side that holds the team spots. Filled by this script.
@export var team_slots: Container
@export var launch_button: Button
## Height of a hero portrait relative to its width (1.0 = square). The portraits are
## sized so that the grid columns exactly fill the width of the left panel.
@export var portrait_aspect := 1.0

## The chosen heroes, in the order they were picked.
var selected_team: Array[CharacterData] = []

var _portraits: Array[HeroPortrait] = []
var _slots: Array[HeroSlot] = []


func _ready() -> void:
	super._ready()  # keeps the close button working

	_build_grid()
	_setup_grid_fit()
	_build_slots()
	launch_button.pressed.connect(launch)
	_refresh_team()


func launch() -> void:
	if selected_team.size() < TEAM_SIZE:
		return
	GameState.start_run(DEFAULT_EXPEDITION_ID, selected_team)
	SceneManager.go_to(&"expedition")


## Heroes the player owns. Locked heroes are never listed, so the grid doesn't
## reveal how many are left to unlock.
func _get_available_heroes() -> Array[CharacterData]:
	return GameState.get_unlocked_heroes()


func _build_grid() -> void:
	for hero in _get_available_heroes():
		var portrait: HeroPortrait = hero_portrait_scene.instantiate()
		portrait.setup(hero)
		portrait.pressed.connect(_on_portrait_pressed.bind(portrait))
		hero_grid.add_child(portrait)
		_portraits.append(portrait)


## The portraits are resized to fill the width of the left panel (no horizontal scrolling,
## the list scrolls vertically if there are many heroes). Re-done whenever the panel is resized.
func _setup_grid_fit() -> void:
	var scroll := hero_grid.get_parent() as ScrollContainer
	if scroll == null:
		return
	hero_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.resized.connect(_fit_grid)
	_fit_grid.call_deferred()  # the layout is not computed yet during _ready


func _fit_grid() -> void:
	var scroll := hero_grid.get_parent() as ScrollContainer
	if scroll == null or hero_grid.columns <= 0:
		return
	var gap := hero_grid.get_theme_constant("h_separation")
	# Keeps room for the vertical scrollbar so it never forces a horizontal one.
	var available := scroll.size.x - scroll.get_v_scroll_bar().get_combined_minimum_size().x
	var cell := floorf((available - gap * (hero_grid.columns - 1)) / hero_grid.columns)
	if cell <= 0.0:
		return
	for portrait in _portraits:
		portrait.custom_minimum_size = Vector2(cell, cell * portrait_aspect)


func _build_slots() -> void:
	for i in TEAM_SIZE:
		var slot: HeroSlot = hero_slot_scene.instantiate()
		slot.clicked.connect(_on_slot_clicked)
		team_slots.add_child(slot)
		_slots.append(slot)


## Click a hero to add him, click him again to remove him.
func _on_portrait_pressed(portrait: HeroPortrait) -> void:
	var hero := portrait.hero
	if selected_team.has(hero):
		selected_team.erase(hero)
	elif selected_team.size() < TEAM_SIZE:
		selected_team.append(hero)
	_refresh_team()  # also puts back the button state if the team was full


## Click a filled spot to remove its hero (the others move up).
func _on_slot_clicked(slot: HeroSlot) -> void:
	var index := _slots.find(slot)
	if index < selected_team.size():
		selected_team.remove_at(index)
		_refresh_team()


func _refresh_team() -> void:
	for i in TEAM_SIZE:
		_slots[i].set_hero(selected_team[i] if i < selected_team.size() else null)
	for portrait in _portraits:
		portrait.set_pick_number(selected_team.find(portrait.hero) + 1)  # 0 = not picked
	launch_button.disabled = selected_team.size() < TEAM_SIZE
