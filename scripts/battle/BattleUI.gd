class_name BattleUI
extends Control
## HUD of the battle: action counter, mana counter and End Turn button.
## Attach to the BattleUI control and assign the three nodes in the inspector.
## It only listens to the Battle signals, so battle.gd needs no UI code.

## If empty, the root of the scene this node was saved in is used.
@export var battle: Battle
@export var action_counter: Label
@export var mana_counter: Label
@export var end_turn_button: Button


func _ready() -> void:
	if battle == null:
		battle = owner as Battle

	battle.actions_changed.connect(_on_actions_changed)
	battle.mana_changed.connect(_on_mana_changed)
	battle.phase_changed.connect(_on_phase_changed)

	end_turn_button.pressed.connect(battle.end_player_turn)
	# A focused button would also react to Enter / Space, which the targeting
	# controller uses to confirm a card.
	end_turn_button.focus_mode = Control.FOCUS_NONE

	# Show the current values (the battle may have started already)
	_on_actions_changed(battle.actions_left)
	_on_mana_changed(battle.mana)
	_on_phase_changed(battle.phase)


func _on_actions_changed(actions_left: int) -> void:
	action_counter.text = "Actions: %d" % actions_left


func _on_mana_changed(mana: int) -> void:
	mana_counter.text = "Mana: %d" % mana


## The player can end the turn at any moment of their own turn, even with
## actions left, but not while a card is resolving or during the enemy turn.
func _on_phase_changed(phase: Battle.Phase) -> void:
	end_turn_button.disabled = phase != Battle.Phase.PLAYER_TURN
