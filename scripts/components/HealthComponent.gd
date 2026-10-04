class_name HealthComponent
extends Node
## Reusable health handler with armor and evasion.
## Add it as a child node of any player or enemy.
## Other systems (cards, UI, AI) talk to it through methods and signals only.

signal health_changed(current: int, maximum: int)
signal armor_changed(current: int)    # UI: show the armor bar only when current > 0
signal evasion_changed(stacks: int)
signal damaged(amount: int)           # health actually lost (armor excluded)
signal healed(amount: int)
signal dodged                         # an attack was evaded
signal died

@export var max_health: int = 100:
	set(value):
		max_health = maxi(value, 1)
		if is_node_ready():
			current_health = mini(current_health, max_health)

var current_health: int
var armor: int = 0
var evasion: int = 0


func _ready() -> void:
	current_health = max_health
	health_changed.emit(current_health, max_health)


## Sets max health and fills it. Call this when spawning from data.
func initialize(max_hp: int) -> void:
	max_health = max_hp
	current_health = max_health
	health_changed.emit(current_health, max_health)


## Applies one hit. Returns the damage that reached health (armor excluded).
## Order: evasion -> armor -> health.
## Call once per hit, so a 3-hit attack consumes up to 3 evasion stacks.
## Use can_be_dodged = false for things like poison, bypass_armor = true for true damage.
func take_damage(amount: int, can_be_dodged: bool = true, bypass_armor: bool = false) -> int:
	if is_dead() or amount <= 0:
		return 0

	if can_be_dodged and evasion > 0:
		remove_evasion(1)
		dodged.emit()
		return 0

	if not bypass_armor and armor > 0:
		var absorbed := mini(amount, armor)
		armor -= absorbed
		amount -= absorbed
		armor_changed.emit(armor)
		if amount == 0:
			return 0

	var dealt := mini(amount, current_health)
	current_health -= dealt
	damaged.emit(dealt)
	health_changed.emit(current_health, max_health)

	if current_health == 0:
		died.emit()
	return dealt


## Restores health, capped at max. Returns the amount actually healed.
func heal(amount: int) -> int:
	if is_dead() or amount <= 0:
		return 0

	var restored := mini(amount, max_health - current_health)
	if restored == 0:
		return 0

	current_health += restored
	healed.emit(restored)
	health_changed.emit(current_health, max_health)
	return restored


func add_armor(amount: int) -> void:
	if is_dead() or amount <= 0:
		return
	armor += amount
	armor_changed.emit(armor)


func remove_armor(amount: int) -> void:
	if amount <= 0 or armor == 0:
		return
	armor = maxi(armor - amount, 0)
	armor_changed.emit(armor)


func add_evasion(stacks: int) -> void:
	if is_dead() or stacks <= 0:
		return
	evasion += stacks
	evasion_changed.emit(evasion)


func remove_evasion(stacks: int) -> void:
	if stacks <= 0 or evasion == 0:
		return
	evasion = maxi(evasion - stacks, 0)
	evasion_changed.emit(evasion)


func is_dead() -> bool:
	return current_health <= 0


func get_health_ratio() -> float:
	return float(current_health) / float(max_health)
