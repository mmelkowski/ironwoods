class_name BattleUI
extends Control
## HUD of the battle: action counter, mana counter, End Turn button, objective
## text and the victory / defeat panels.
## Attach to the BattleUI control and assign the nodes in the inspector
## (the objective label and the two panels are optional).
## It only listens to the Battle signals, so battle.gd needs no UI code.

## If empty, the root of the scene this node was saved in is used.
@export var battle: Battle
@export var action_counter: Label
@export var mana_counter: Label
@export var end_turn_button: Button
## Optional: shows the objective and its progress ("Defeat all enemies / Enemies left: 3").
@export var objective_label: Label
## Optional: panels shown when the battle ends. Hidden at the start.
@export var victory_panel: Control
@export var defeat_panel: Control


func _ready() -> void:
	if battle == null:
		battle = owner as Battle

	battle.actions_changed.connect(_on_actions_changed)
	battle.mana_changed.connect(_on_mana_changed)
	battle.phase_changed.connect(_on_phase_changed)
	battle.objective_updated.connect(_refresh_objective)
	battle.battle_ended.connect(_on_battle_ended)

	end_turn_button.pressed.connect(battle.end_player_turn)
	# A focused button would also react to Enter / Space, which the targeting
	# controller uses to confirm a card.
	end_turn_button.focus_mode = Control.FOCUS_NONE

	# Show the current values (the battle may have started already)
	_on_actions_changed(battle.actions_left)
	_on_mana_changed(battle.mana)
	_on_phase_changed(battle.phase)
	_refresh_objective()
	for panel in [victory_panel, defeat_panel]:
		if panel != null:
			panel.hide()


func _on_actions_changed(actions_left: int) -> void:
	action_counter.text = "Actions: %d" % actions_left


func _on_mana_changed(mana: int) -> void:
	mana_counter.text = "Mana: %d" % mana


## The player can end the turn at any moment of their own turn, even with
## actions left, but not while a card is resolving or during the enemy turn.
func _on_phase_changed(phase: Battle.Phase) -> void:
	end_turn_button.disabled = phase != Battle.Phase.PLAYER_TURN


func _refresh_objective() -> void:
	# The objective only starts with the battle, after this node is ready
	if objective_label == null or battle.objective == null or not battle.objective.is_started():
		return
	var text := battle.objective.description
	var progress := battle.objective.get_progress_text()
	if progress != "":
		text += "\n" + progress
	objective_label.text = text


func _on_battle_ended(victory: bool) -> void:
	if victory_panel != null:
		victory_panel.visible = victory
	if defeat_panel != null:
		defeat_panel.visible = not victory
