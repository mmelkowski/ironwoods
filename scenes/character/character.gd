class_name Character
extends Node2D
## On-screen representation of one hero or enemy.
## Assign `data` in the inspector, or call setup(data) when spawning from code.

## Size in pixels of one status icon above/next to the health bar, and of its stack number.
const STATUS_ICON_SIZE := 80
const STATUS_FONT_SIZE := 40

signal clicked(character: Character)  # for card targeting
signal died(character: Character)
signal statuses_changed

const TILE_SIZE := 32
const GROUP_ALLIES := &"allies"
const GROUP_ENEMIES := &"enemies"

# Intent cutout: size of the square cut around the target's head (CharacterData.head_position).
const INTENT_CUTOUT_SIZE := Vector2(16, 16)

# The UI node is placed so that the BOTTOM of the health bar sits this many pixels above the head
# of the character (CharacterData.head_position). Everything else of the UI (armor, statuses,
# intent icon) is stacked above that line, wherever it is in character_ui.tscn.
const UI_HEIGHT_ABOVE_HEAD := 20.0

# The clickable circle is the width of the sprite on screen (size_in_tiles * TILE_SIZE * the scale
# of the Sprite2D) times this factor. Below 1.0 it is a bit smaller than the sprite.
const CLICK_RADIUS_FACTOR := 1.0


@export var data: CharacterData

var _start_health := -1
var _ui_bottom_target := 0.0  # where the bottom of the health bar must be (character space)

## Enemies only: what this enemy will do on its next turn (see EnemyIntent).
## Setting it updates the cutout and the label above the enemy's head.
var intent: EnemyIntent:
	set(value):
		intent = value
		refresh_intent()

## Enemies only: the character the current intent aims at (the hero to hit, or the enemy to buff).
## Read-only, it comes from `intent`. Null for an AOE intent or when nothing is planned.
var intent_target: Character:
	get:
		if intent == null or not is_instance_valid(intent.target):
			return null
		return intent.target


## Persistent statuses (Bleeding, Stun...), created in _ready(). Armor and heal are not
## stored here: they act on the HealthComponent at once (see apply_status).
var status_component: StatusComponent

## StatusData -> stacks (read-only view of status_component).
var statuses: Dictionary:
	get: return status_component.stacks if status_component != null else {}

@onready var health: HealthComponent = %HealthComponent
@onready var sprite: Sprite2D = %Sprite
@onready var ui = %UI  # root of character_ui.tscn: Control or Node2D, only its position is used
@onready var health_bar: ProgressBar = %UI/%HealthBar
@onready var armor_bar: ProgressBar = %UI/%ArmorBar
## Values written on the bars (Label children of the bars in character_ui.tscn).
@onready var health_label: Label = %UI/%HealthValue
@onready var armor_label: Label = %UI/%ArmorValue
## Optional: an HBoxContainer in character_ui.tscn (unique name %StatusIcons) that shows the
## statuses of the character. Without it statuses work but are not displayed.
@onready var status_icons: HBoxContainer = get_node_or_null("%UI/%StatusIcons")
@onready var intent_icon: Sprite2D = %UI/%IntentIcon
## Optional: a Label in character_ui.tscn (unique name %IntentLabel), next to the intent icon, that shows
## the planned action ("Stab", "Heavy 1"). Without it intents work but the name is not displayed.
@onready var intent_label: Label = get_node_or_null("%UI/%IntentLabel")
@onready var click_area: Area2D = %ClickArea
@onready var click_shape: CollisionShape2D = %ClickShape
@onready var shape := click_shape.shape as CircleShape2D


func _ready() -> void:
	health.health_changed.connect(_on_health_changed)
	health.armor_changed.connect(_on_armor_changed)
	health.died.connect(func(): died.emit(self))
	status_component = StatusComponent.new(health)
	status_component.name = "StatusComponent"
	add_child(status_component)
	status_component.changed.connect(_on_statuses_changed)
	_on_statuses_changed()
	click_area.input_event.connect(_on_click_area_input_event)
	# The bars move inside the UI when the armor bar appears/disappears: keep the bottom in place.
	health_bar.item_rect_changed.connect(_update_ui_position_later)
	refresh_intent()  # hidden until an intent is assigned

	if data:
		_apply_data()


## Use this when spawning from code:
##   var c = character_scene.instantiate()
##   c.setup(preload("res://data/characters/wolf.tres"))
##   add_child(c)
## start_health: health at the start (-1 = full), for heroes who keep their health
## from one battle of an expedition to the next.
func setup(new_data: CharacterData, start_health: int = -1) -> void:
	data = new_data
	_start_health = start_health
	if is_node_ready():
		_apply_data()


func is_ally() -> bool:
	return data.team == CharacterData.Team.ALLY


func is_dead() -> bool:
	return health.is_dead()


## Placeholder target highlight (tints the sprite). Swap for an outline or marker later.
func set_highlighted(on: bool) -> void:
	sprite.modulate = Color(1.0, 0.9, 0.4) if on else Color.WHITE


## Gives `stacks` of a status. What a stack means depends on StatusData.effect:
## ARMOR / HEAL: that many points, applied at once.
## Anything else (Bleeding, Stun...) is stored in the StatusComponent and ticked by Battle.
func apply_status(status: StatusData, stacks: int) -> void:
	if status == null or stacks <= 0 or is_dead():
		return
	match status.get_effect():
		StatusData.Effect.ARMOR:
			health.add_armor(stacks)
		StatusData.Effect.HEAL:
			health.heal(stacks)
		StatusData.Effect.CLEANSE:
			status_component.remove_debuffs()
		_:
			status_component.add(status, stacks)


## One incoming hit: dodged by Evasion (returns 0), otherwise armor then health.
## A hit that is not dodged wakes a sleeper, even if the armor absorbed all of it
## (to wake only when health is lost, test `dealt > 0` instead of `amount > 0`).
## Damage over time (Bleeding, Poison) does not come through here, so it never wakes.
## Returns the health actually lost. Battle uses this instead of health.take_damage().
func take_hit(amount: int) -> int:
	if status_component.try_dodge():
		return 0
	var dealt := health.take_damage(amount, false)
	if amount > 0:
		status_component.wake_up()
	return dealt


## A stunned character cannot act (heroes: their cards can't be played; enemies skip their attack).
func is_stunned() -> bool:
	return status_component.is_stunned()


## Stunned or asleep: cannot act. This is what Battle checks (cards and enemy turns).
func is_incapacitated() -> bool:
	return status_component.is_incapacitated()


## Makes the character look at a world position by flipping the sprite.
## The art is drawn facing LEFT, so it is flipped when the target is on the right.
## Only the sprite is flipped, so the health bars stay readable.
func face_towards(world_position: Vector2) -> void:
	var dx := world_position.x - global_position.x
	if not is_zero_approx(dx):
		sprite.flip_h = dx > 0.0


## Redraws the intent display (head cutout + action text). Battle calls it after changing
## something inside the intent (windup turns left, new target).
func refresh_intent() -> void:
	_update_intent_icon()
	_update_intent_label()


## Writes the planned action ("Stab", "Heavy 1"...) in the %IntentLabel of the UI scene.
## The color is a tint (self_modulate): keep the label's own font color white in the scene.
func _update_intent_label() -> void:
	if intent_label == null or not is_node_ready():
		return
	if intent == null:
		intent_label.hide()
		return
	intent_label.text = intent.get_text()
	intent_label.self_modulate = intent.action.get_color()
	intent_label.show()


## Shows the head of the intent target's sprite above this character,
## or hides the cutout when there is no target (allies never have one, AOE has none).
func _update_intent_icon() -> void:
	if not is_node_ready():
		return

	var source: AtlasTexture = null
	if intent_target != null:
		source = intent_target.sprite.texture as AtlasTexture
	if source == null:
		intent_icon.hide()
		return

	var crop := Rect2(
		source.region.position + intent_target.data.head_position - INTENT_CUTOUT_SIZE / 2.0,
		INTENT_CUTOUT_SIZE)
	var icon := AtlasTexture.new()
	icon.atlas = source.atlas
	icon.region = crop.intersection(source.region)  # never bleed into a neighbouring tile
	intent_icon.texture = icon
	intent_icon.show()


func _apply_data() -> void:
	# Team (groups let you do get_tree().get_nodes_in_group("enemies"))
	remove_from_group(GROUP_ALLIES)
	remove_from_group(GROUP_ENEMIES)
	add_to_group(GROUP_ALLIES if is_ally() else GROUP_ENEMIES)

	# Sprite cut out of the tileset
	var atlas := AtlasTexture.new()
	atlas.atlas = data.tileset
	atlas.region = Rect2(
		Vector2(data.tile_coords * TILE_SIZE),
		Vector2(data.size_in_tiles * TILE_SIZE))
	sprite.texture = atlas
	shape.radius = (atlas.region.size.x * CLICK_RADIUS_FACTOR ) + 5
	_place_ui(atlas.region.size)

	# Stats
	health.initialize(data.max_health, _start_health)
	health.add_armor(data.starting_armor)
	for status: StatusData in data.starting_statuses:
		apply_status(status, data.starting_statuses[status])

	# Make sure the bars start in the right state (hidden when armor is 0)
	_on_armor_changed(health.armor)
	_refresh_status_icons()


## Computes where the bottom of the health bar must be (y in the character's space):
## UI_HEIGHT_ABOVE_HEAD above the head. The head is data.head_position, measured in texture
## pixels from the top-left corner of the sprite.
func _place_ui(sprite_size: Vector2) -> void:
	var top := sprite.position.y + sprite.offset.y * sprite.scale.y
	if sprite.centered:
		top -= sprite_size.y * sprite.scale.y / 2.0
	var head_y := top + data.head_position.y * sprite.scale.y
	_ui_bottom_target = head_y - UI_HEIGHT_ABOVE_HEAD
	_update_ui_position()
	_update_ui_position_later()


## The containers of the UI only know their final sizes after a couple of frames.
func _update_ui_position_later() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_inside_tree():
		_update_ui_position()


## Moves the UI node so that the bottom of the health bar sits on _ui_bottom_target.
## Measured from the real transforms, so the scale and layout of character_ui.tscn don't matter.
func _update_ui_position() -> void:
	if data == null:
		return
	var bar_bottom: Vector2 = health_bar.get_global_transform() * Vector2(0.0, health_bar.size.y)
	var bar_bottom_in_ui: Vector2 = ui.get_global_transform().affine_inverse() * bar_bottom
	ui.position.y = _ui_bottom_target - bar_bottom_in_ui.y * ui.scale.y


func _on_statuses_changed() -> void:
	_refresh_status_icons()
	statuses_changed.emit()


## Rebuilds the status row. A status shows its icon with a number in the bottom-right corner
## (turns left, see StatusData.get_display_number), or "Name 3" as text when it has no icon.
func _refresh_status_icons() -> void:
	if status_icons == null or status_component == null:
		return
	for child in status_icons.get_children():
		status_icons.remove_child(child)
		child.queue_free()
	for status: StatusData in status_component.stacks:
		var title := status.display_name if status.display_name != "" else str(status.id)
		var number := status.get_display_number(status_component.stacks[status])
		status_icons.add_child(_make_status_entry(status.icon, title, number))
	status_icons.visible = status_icons.get_child_count() > 0


func _make_status_entry(icon: Texture2D, title: String, number: int) -> Control:
	if icon == null:
		var text := Label.new()
		text.text = "%s %d" % [title, number]
		_style_status_label(text)
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return text

	var holder := Control.new()
	holder.custom_minimum_size = Vector2(STATUS_ICON_SIZE, STATUS_ICON_SIZE)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE  # must not block clicks on the character

	var picture := TextureRect.new()
	picture.texture = icon
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # keeps pixel art sharp
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(picture)
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	if number > 0:
		var count := Label.new()
		count.text = str(number)
		_style_status_label(count)
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(count)
		# The number's top-right corner sits on the icon's bottom-right corner: the label is pinned
		# to that corner and grows to the left and downward, whatever the size of the text.
		count.anchor_left = 1.0
		count.anchor_right = 1.0
		count.anchor_top = 1.0
		count.anchor_bottom = 1.0
		count.offset_left = 0.0
		count.offset_right = 0.0
		count.offset_top = 0.0
		count.offset_bottom = 0.0
		count.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		count.grow_vertical = Control.GROW_DIRECTION_END
	return holder


func _style_status_label(label: Label) -> void:
	label.add_theme_font_size_override("font_size", STATUS_FONT_SIZE)
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_color_override("font_outline_color", Color.BLACK)


func _on_health_changed(current: int, maximum: int) -> void:
	health_bar.max_value = maximum
	health_bar.value = current
	health_label.text = "%d" % current # "%d/%d" % [current, maximum]
	armor_bar.max_value = maximum  # armor bar is drawn relative to max health


func _on_armor_changed(current: int) -> void:
	armor_bar.visible = current > 0
	armor_bar.value = current
	armor_label.text = str(current)


func _on_click_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(self)
