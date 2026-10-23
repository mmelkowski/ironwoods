@tool
class_name StatusData
extends Resource
## One kind of status or value effect (Bleeding, Stun, Armor, Heal, Evasion...).
## It is authored once as a .tres and referenced by StatusApplication (cards).
##
## What `stacks` means depends on `effect`:
##   ARMOR   : points of armor added (50 = +50 armor, 1 point = 1 hp). Instant, nothing stays on the character.
##   HEAL    : health restored. Instant.
##   EVASION : number of hits that will be dodged (kept by HealthComponent).
##   BLEED   : damage dealt at the start of the owner's turn, then loses `decay_per_turn` stacks.
##   STUN    : number of turns skipped, loses 1 stack at the end of each turn.
##   CLEANSE : removes every debuff from the target at once (`stacks` is ignored, use 1). Instant.
##   NONE    : a plain marker, stored on the character (for future effects/relics).

enum DurationType { TURNS, USES }
enum Effect { NONE, ARMOR, HEAL, EVASION, BLEED, STUN, CLEANSE }

@export var id: StringName
@export var display_name := ""
@export_multiline var description := ""
@export var icon: Texture2D

@export var effect: Effect = Effect.NONE:
	set(value):
		effect = value
		notify_property_list_changed()

## Marks a negative status, so CLEANSE removes it. BLEED and STUN are always debuffs;
## tick this for any other negative status you create.
@export var debuff := false

## TURNS: stacks go down at the end of the owner's turn. USES: stacks only go down when
## something consumes them (StatusComponent.consume). Hidden for instant effects.
@export var duration_type: DurationType = DurationType.TURNS
## TURNS only: how many stacks are lost at the end of each turn (0 = never expires).
@export var decay_per_turn := 1
## BLEED only: damage ignores armor (it goes straight to health).
@export var bypass_armor := true


## Older Evasion resources have effect NONE and the id "evasion": still handled.
func get_effect() -> Effect:
	if effect == Effect.NONE and id == &"evasion":
		return Effect.EVASION
	return effect


## True for negative statuses (the ones a CLEANSE card removes).
func is_debuff() -> bool:
	return debuff or effect == Effect.BLEED or effect == Effect.STUN


## Instant value effects: applied at once, nothing is stored on the character.
func is_value_effect() -> bool:
	return get_effect() == Effect.ARMOR or get_effect() == Effect.HEAL


func _validate_property(property: Dictionary) -> void:
	var instant := is_value_effect() or get_effect() in [Effect.EVASION, Effect.CLEANSE]
	if instant and property.name in ["duration_type", "decay_per_turn"]:
		property.usage = PROPERTY_USAGE_NO_EDITOR
	if effect != Effect.BLEED and property.name == "bypass_armor":
		property.usage = PROPERTY_USAGE_NO_EDITOR
