class_name CardDeck
extends RefCounted
## The team's shared deck: draw pile, hand and discard pile.
## Knows nothing about the battle rules, it only moves cards between piles.

signal hand_changed

const MAX_HAND_SIZE := 6

var draw_pile: Array[CardInstance] = []
var hand: Array[CardInstance] = []
var discard_pile: Array[CardInstance] = []


## Builds the draw pile from the deck of every given hero, then shuffles it.
func build_from(heroes: Array[Character]) -> void:
	draw_pile.clear()
	hand.clear()
	discard_pile.clear()
	for hero in heroes:
		for card_data in hero.data.deck:
			draw_pile.append(CardInstance.new(card_data, hero))
	draw_pile.shuffle()
	hand_changed.emit()


## Draws until the hand is full. Does nothing if the hand is already full.
func draw_to_full() -> void:
	while hand.size() < MAX_HAND_SIZE:
		if not _draw_one():
			break
	hand_changed.emit()


func discard(card: CardInstance) -> void:
	hand.erase(card)
	discard_pile.append(card)
	hand_changed.emit()


## Removes every card of a hero (used when a hero dies).
func remove_cards_of(hero: Character) -> void:
	for pile in [draw_pile, hand, discard_pile]:
		for i in range(pile.size() - 1, -1, -1):
			if pile[i].caster == hero:
				pile.remove_at(i)
	hand_changed.emit()


func _draw_one() -> bool:
	if draw_pile.is_empty():
		if discard_pile.is_empty():
			return false
		draw_pile.append_array(discard_pile)
		discard_pile.clear()
		draw_pile.shuffle()
	hand.append(draw_pile.pop_back())
	return true
