class_name CardInstance
extends RefCounted
## Runtime version of a card. Create one when the card is drawn; throw it away
## when it's discarded, so buffs never leak into the shared CardData.
##
## Buff cards edit this, never the CardData:
##   card.critical = true
##   card.damage += 3

var data: CardData
## The hero who owns this card (it comes from their deck).
var caster: Character
var damage: int
var critical: bool
var mana_generation: int
var mana_cost: int


func _init(card_data: CardData, card_caster: Character) -> void:
	data = card_data
	caster = card_caster
	damage = card_data.damage
	critical = card_data.critical
	mana_generation = card_data.mana_generation
	mana_cost = card_data.mana_cost


## All effects of the card for a given trigger (ON_PLAY or ON_KILL).
func get_effects(trigger: StatusApplication.Trigger) -> Array[StatusApplication]:
	var result: Array[StatusApplication] = []
	for effect in data.effects:
		if effect.trigger == trigger:
			result.append(effect)
	return result
