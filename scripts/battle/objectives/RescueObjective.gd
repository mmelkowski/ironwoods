class_name RescueObjective
extends BattleObjective
## Free a hostage. The hostage (a NEUTRAL character with Role.HOSTAGE) is guarded by one or more
## enemies with Role.CAPTOR. When the last captor is dead, `rescue_card` is added to the hand of a
## hero; playing it frees the hostage and wins the battle.
##
## Setup: a scene whose root is a RescueObjective node, with `rescue_card` assigned, set as
## EncounterData.objective_scene; the captor and the hostage go in EncounterData.enemies.
## The card is a normal CardData: SUPPORT, target SELF, damage 0.

@export var rescue_card: CardData

var _captors: Array[Character] = []
var _captor_names: Array[String] = []
var _hostage_names: Array[String] = []
var _card: CardInstance  # the card in the hand right now (null before the captors fall)
var _rescued := false
## No hostage or no card (data error): behave like KillAllObjective instead of a fight nobody can win.
var _fallback := false


func _init() -> void:
	description = "Rescue the hostage"


func _on_start() -> void:
	for neutral in battle.neutrals:
		if neutral.data.has_role(CharacterData.Role.HOSTAGE):
			_hostage_names.append(neutral.data.display_name)
	for enemy in battle.enemies:
		if enemy.data.has_role(CharacterData.Role.CAPTOR):
			_captors.append(enemy)
			_captor_names.append(enemy.data.display_name)

	if _hostage_names.is_empty() or rescue_card == null:
		_fallback = true
		push_error("RescueObjective: needs a NEUTRAL character with the HOSTAGE role in the battle and a rescue_card, falling back to 'defeat all enemies'.")
		description = "Defeat all enemies"
		return

	description = "Rescue " + ", ".join(_hostage_names)
	battle.card_played.connect(_on_card_played)
	if _captors.is_empty():
		push_warning("RescueObjective: no enemy has the CAPTOR role, the rescue card is given right away.")
		_grant_card()


func on_character_died(character: Character) -> void:
	if _fallback or _rescued:
		return
	if _card != null and character == _card.caster:
		_card = null  # the deck dropped it with its owner: give it to someone else
	if _card == null and _alive_captors() == 0:
		_grant_card()


func is_complete() -> bool:
	if _fallback:
		return battle.enemies.is_empty()
	return _rescued


func get_progress_text() -> String:
	if _fallback:
		return "Enemies left: %d" % battle.enemies.size()
	if _rescued:
		return ""
	if _card != null:
		return "Play \"%s\" to free them" % rescue_card.display_name
	var names: Array[String] = []
	for i in _captors.size():
		if battle.enemies.has(_captors[i]):
			names.append(_captor_names[i])
	return "Defeat " + ", ".join(names)


func _on_card_played(card: CardInstance) -> void:
	if card == _card:
		_rescued = true  # the Battle checks is_complete() right after card_played


func _alive_captors() -> int:
	var count := 0
	for captor in _captors:
		if battle.enemies.has(captor):
			count += 1
	return count


## Gives the card to a hero who can play it now (not stunned or asleep), else to any living hero.
func _grant_card() -> void:
	var holder: Character = null
	for hero in battle.allies:
		if not hero.is_incapacitated():
			holder = hero
			break
	if holder == null and not battle.allies.is_empty():
		holder = battle.allies[0]
	if holder == null:
		return
	_card = CardInstance.new(rescue_card, holder)
	battle.deck.add_to_hand(_card)
