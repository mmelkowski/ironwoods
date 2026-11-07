@tool
class_name StatusData
extends Resource
## One kind of status or value effect (Bleeding, Stun, Armor, Heal, Evasion...).
## It is authored once as a .tres and referenced by StatusApplication (cards).
##
## What `stacks` means depends on `effect`:
##   ARMOR   : points of armor added (50 = +50 armor, 1 point = 1 hp). Instant, nothing stays on the character.
##   HEAL    : health restored. Instant.
##   EVASION : with duration USES, each stack dodges one hit (and is consumed). With duration TURNS,
##             it dodges every hit while it lasts.
##   BLEED   : damage at the start of the owner's turn = `tick_damage` x stacks (stacking makes it
##             stronger), then it loses `decay_per_turn` stacks.
##   POISON  : damage at the start of the owner's turn = `tick_damage`, whatever the stacks (they are only
##             its duration: stacking never makes it stronger, so spread it), then it loses `decay_per_turn`.
##   STUN    : number of turns skipped, loses 1 stack at the end of each turn.
##   SLEEP   : like STUN (the owner cannot act, loses 1 stack at the end of each turn), but any hit
##             that damages the owner wakes it up at once: the status is removed (see Character.take_hit).
##             Bleeding / Poison ticks do not wake it.
##   CLEANSE : removes every debuff from the target at once (`stacks` is ignored, use 1). Instant.
##   FORM    : an animal form of a character (the druid). `stacks` = the number of turns it lasts (use TURNS
##             duration with decay 1). A character has ONE form at a time: a new form replaces the old one.
##             While it is up: its sprite replaces the character's (form_tileset...), `form_grants` were given
##             when it started and are taken back when it ends (what is left of them), the owner's attack cards
##             also put `attack_statuses` on every enemy they hit, and give at least `attack_knockback`.
##             See StatusComponent._add_form. Forms work for hero cards (Battle.play_card) only.
##   NONE    : a plain marker, stored on the character (for future effects/relics). With duration USES
##             it is also the way to build a stack that cards consume (arcane charges, rage): it never decays
##             and StatusComponent.consume / consume_all take stacks away.

enum DurationType { TURNS, USES }
enum Effect { NONE, ARMOR, HEAL, EVASION, BLEED, STUN, CLEANSE, POISON, SLEEP, FORM }  # append only: saved as integers

const TILE_SIZE := 32

@export var id: StringName
@export var display_name := ""
@export_multiline var description := ""
@export var icon: Texture2D

@export var effect: Effect = Effect.NONE:
	set(value):
		effect = value
		notify_property_list_changed()

## Marks a negative status, so CLEANSE removes it. BLEED, POISON, STUN and SLEEP are always debuffs;
## tick this for any other negative status you create.
@export var debuff := false

## TURNS: stacks go down at the end of the owner's turn. USES: stacks only go down when
## something consumes them (StatusComponent.consume). Hidden for instant effects.
@export var duration_type: DurationType = DurationType.TURNS
## TURNS only: how many stacks are lost at the end of each turn (0 = never expires).
@export var decay_per_turn := 1
## BLEED / POISON: damage dealt at the start of the owner's turn.
## BLEED: tick_damage x stacks. POISON: tick_damage, whatever the stacks.
@export_range(0, 999) var tick_damage := 1
## BLEED / POISON: damage ignores armor (it goes straight to health).
@export var bypass_armor := true

@export_group("Form")
## FORM: given when the form starts, taken back when it ends: status -> stacks. Armor (Bear 20) and
## Evasion (Ferret 2) work; what is left of them is taken back (armor already spent is not).
@export var form_grants: Dictionary[StatusData, int] = {}
## FORM: put on every living enemy hit by an attack card of the owner: status -> stacks
## (Snake: Poison 1, Wolf: Bleeding 1).
@export var attack_statuses: Dictionary[StatusData, int] = {}
## FORM: every attack card of the owner has at least this knockback (and so does its move-action push):
## 0 none, 1 standard (48 px), 2 forceful (96 px). Ibex: 2.
@export_enum("None:0", "Standard:1", "Forceful:2") var attack_knockback := 0
## FORM: the sprite of the form, cut like a character's (32x32 tiles, drawn facing left).
@export var form_tileset: Texture2D
## FORM: tile position in form_tileset, in tiles (not pixels).
@export var form_tile_coords := Vector2i.ZERO
## FORM: size in tiles (1, 1 = 32x32).
@export var form_size_in_tiles := Vector2i.ONE
## FORM: where the head is, in pixels from the top-left of the form sprite (health bar and intent icon).
@export var form_head_position := Vector2(16, 8)


## Older Evasion resources have effect NONE and the id "evasion": still handled.
func get_effect() -> Effect:
	if effect == Effect.NONE and id == &"evasion":
		return Effect.EVASION
	return effect


func is_form() -> bool:
	return get_effect() == Effect.FORM


## FORM: the sprite of the form (null without form_tileset).
func get_form_sprite() -> AtlasTexture:
	if form_tileset == null:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = form_tileset
	atlas.region = Rect2(Vector2(form_tile_coords * TILE_SIZE), Vector2(form_size_in_tiles * TILE_SIZE))
	return atlas


## The number shown on the status icon: for BLEED its stacks (the intensity: damage = tick_damage x stacks),
## otherwise the turns left for a TURNS status that expires, or its stacks (hits left for a USES
## status, charges, or a permanent status).
func get_display_number(stacks: int) -> int:
	if get_effect() == Effect.BLEED:
		return stacks
	if duration_type == DurationType.TURNS and decay_per_turn > 0:
		return ceili(float(stacks) / decay_per_turn)
	return stacks


## True for negative statuses (the ones a CLEANSE card removes).
func is_debuff() -> bool:
	return debuff or effect == Effect.BLEED or effect == Effect.POISON or effect == Effect.STUN or effect == Effect.SLEEP


## True for the statuses that deal damage at the start of the owner's turn.
func is_tick_effect() -> bool:
	return get_effect() == Effect.BLEED or get_effect() == Effect.POISON


## Damage dealt at the start of the owner's turn with `stacks` stacks (0 for other effects).
## BLEED scales with the stacks, POISON does not.
func get_tick_damage(stacks: int) -> int:
	match get_effect():
		Effect.BLEED:
			return maxi(tick_damage, 0) * maxi(stacks, 0)
		Effect.POISON:
			return maxi(tick_damage, 0) if stacks > 0 else 0
	return 0


## Instant value effects: applied at once, nothing is stored on the character.
func is_value_effect() -> bool:
	return get_effect() == Effect.ARMOR or get_effect() == Effect.HEAL


func _validate_property(property: Dictionary) -> void:
	var instant := is_value_effect() or get_effect() == Effect.CLEANSE
	if instant and property.name in ["duration_type", "decay_per_turn"]:
		property.usage = PROPERTY_USAGE_NO_EDITOR
	var ticks := effect == Effect.BLEED or effect == Effect.POISON
	if not ticks and property.name in ["tick_damage", "bypass_armor"]:
		property.usage = PROPERTY_USAGE_NO_EDITOR
	if not is_form() and property.name in ["Form", "form_grants", "attack_statuses", "attack_knockback",
			"form_tileset", "form_tile_coords", "form_size_in_tiles", "form_head_position"]:
		property.usage = PROPERTY_USAGE_NO_EDITOR
