extends Control
## The expedition screen: the player sees the whole graph and picks the next node.
## Each node is then played: battle, camp, event... When the END node is reached
## (or the party is defeated) the expedition ends and the player goes back to the hub.
##
## All the nodes below use "Access as Unique Name" (see the scene tree in the docs).

const CAMP_HEAL_RATIO := 0.3  # share of max health recovered at a camp

## How the expedition ended. The loot is kept in every case, only a completed
## expedition also gives its bonus.
enum Outcome { COMPLETED, ABANDONED, DEFEATED }

## TEMPORARY, until battles give real loot: what a won battle gives.
const STUB_BATTLE_LOOT := {&"wood": 2}

@onready var map: ExpeditionMap = %Map
@onready var map_scroll: ScrollContainer = %MapScroll
@onready var title_label: Label = %TitleLabel
@onready var goal_label: Label = %GoalLabel
@onready var team_panel: Container = %TeamPanel
## Optional: add a Button named AbandonButton ("Access as Unique Name") to get the abandon feature.
@onready var abandon_button: Button = get_node_or_null("%AbandonButton")
@onready var dialog_layer: Control = %DialogLayer
@onready var dialog_title: Label = %DialogTitle
@onready var dialog_body: Label = %DialogBody
@onready var dialog_buttons: Container = %DialogButtons

var _expedition: ExpeditionData
var _run: RunState


func _ready() -> void:
	_ensure_run()
	_run = GameState.run
	_expedition = GameState.get_run_expedition()
	if _expedition == null:
		push_error("Expedition: unknown expedition '%s'." % _run.expedition_id)
		return

	title_label.text = _expedition.display_name
	goal_label.text = _expedition.goal
	dialog_layer.hide()
	map.build(_expedition)
	map.node_chosen.connect(_on_node_chosen)
	if abandon_button != null:
		abandon_button.pressed.connect(_on_abandon_pressed)
	else:
		push_warning("Expedition: no AbandonButton in the scene, the player can't abandon.")

	if _run.current_node_id == &"":
		# A new run starts on the START node, which needs no resolution
		_run.enter_node(_expedition.get_start().id)
		_run.resolve_node()
		GameState.save_game()  # the expedition is saved as soon as it starts
	_refresh()

	# Coming back from a battle, or a run loaded in the middle of a node
	if not _run.node_resolved:
		_resume_node(_expedition.get_node_by_id(_run.current_node_id))


## Lets the scene run on its own (F6) with a test run.
func _ensure_run() -> void:
	if GameState.has_run():
		return
	push_warning("Expedition: no run in progress, starting a test run.")
	var team: Array[CharacterData] = []
	for hero in GameState.get_unlocked_heroes():
		if team.size() < 3:
			team.append(hero)
	GameState.start_run(&"first_expedition", team)


func _refresh() -> void:
	map.refresh(_run)
	_refresh_team()
	_scroll_to_current.call_deferred()


func _scroll_to_current() -> void:
	var button := map.get_button(_run.current_node_id)
	if button != null:
		map_scroll.ensure_control_visible(button)


## The health of each hero, carried over from battle to battle.
func _refresh_team() -> void:
	for child in team_panel.get_children():
		team_panel.remove_child(child)
		child.queue_free()
	for hero in GameState.get_run_team():
		var label := Label.new()
		label.text = "%s   %d / %d" % [hero.display_name, _run.get_health(hero.id), hero.max_health]
		team_panel.add_child(label)


# ---------------------------------------------------------------------------
# Playing the nodes
# ---------------------------------------------------------------------------

func _on_node_chosen(node: ExpeditionNode) -> void:
	_run.enter_node(node.id)
	# No save here: the game only saves on the map, between nodes (see _resolve)
	_refresh()
	_play_node(node)


## A node was left unfinished. If it is a battle that just ended, its result is
## waiting in the run. Otherwise the node simply starts again.
func _resume_node(node: ExpeditionNode) -> void:
	if node.has_encounter() and _run.battle_result != RunState.BattleResult.NONE:
		var victory := _run.battle_result == RunState.BattleResult.VICTORY
		_run.battle_result = RunState.BattleResult.NONE
		_on_battle_finished(victory)
	else:
		_play_node(node)


func _play_node(node: ExpeditionNode) -> void:
	match node.type:
		ExpeditionNode.Type.BATTLE, ExpeditionNode.Type.BOSS:
			_start_battle(node)
		ExpeditionNode.Type.CAMP:
			_rest(node)
		ExpeditionNode.Type.EVENT:
			_play_event(node)
		ExpeditionNode.Type.END:
			_finish(Outcome.COMPLETED)
		_:
			_resolve()


## The node is done: the player can pick the next one.
func _resolve() -> void:
	_run.resolve_node()
	GameState.save_game()
	_refresh()


## Goes to the battle scene, which reads the encounter of the current node and
## writes its result in the run. The player comes back here when it ends.
## Without a battle scene (testing the map alone) a stub dialog stands in.
func _start_battle(node: ExpeditionNode) -> void:
	if await SceneManager.go_to(&"battle"):
		return
	_show_battle_stub(node)


func _show_battle_stub(node: ExpeditionNode) -> void:
	_show_dialog(node.title, "Battle (not implemented yet).\nChoose the result:", [
		{"text": "Victory", "action": _on_battle_finished.bind(true)},
		{"text": "Defeat", "action": _on_battle_finished.bind(false)},
	])


func _on_battle_finished(victory: bool) -> void:
	if not victory:
		_finish(Outcome.DEFEATED)
		return
	for id in STUB_BATTLE_LOOT:
		_run.add_loot(id, STUB_BATTLE_LOOT[id])
	_resolve()


## The party rests and recovers a share of its max health.
func _rest(node: ExpeditionNode) -> void:
	var report := ""
	for hero in GameState.get_run_team():
		var before := _run.get_health(hero.id)
		var after := mini(hero.max_health, before + ceili(hero.max_health * CAMP_HEAL_RATIO))
		_run.set_health(hero.id, after)
		report += "%s recovers %d health\n" % [hero.display_name, after - before]
	_show_dialog(node.title, report.strip_edges(), [{"text": "Continue", "action": _resolve}])


## STUB: story events come later.
func _play_event(node: ExpeditionNode) -> void:
	_show_dialog(node.title, node.description if node.description != "" else "Nothing happens.",
		[{"text": "Continue", "action": _resolve}])


func _on_abandon_pressed() -> void:
	_show_dialog("Abandon the expedition?",
		"The party goes back to the hub and keeps the loot gathered so far,\nbut not the bonus for completing the expedition.", [
		{"text": "Abandon", "action": _finish.bind(Outcome.ABANDONED)},
		{"text": "Keep going", "action": Callable()},
	])


## Ends the expedition and shows what the party brings back.
func _finish(outcome: Outcome) -> void:
	var result := GameState.end_run(outcome == Outcome.COMPLETED)

	var report := ""
	match outcome:
		Outcome.DEFEATED:
			report = "The party was defeated, but keeps what it gathered.\n\n"
		Outcome.ABANDONED:
			report = "The party comes back early.\n\n"
	report += "Loot:\n" + _describe_resources(result["loot"])
	if outcome == Outcome.COMPLETED:
		report += "\n\nCompletion bonus:\n" + _describe_resources(result["bonus"])

	var title := "Expedition complete"
	if outcome == Outcome.ABANDONED:
		title = "Expedition abandoned"
	elif outcome == Outcome.DEFEATED:
		title = "Expedition failed"
	_show_dialog(title, report, [{"text": "Return to the hub", "action": SceneManager.go_to.bind(&"hub")}])
	_refresh_team()


func _describe_resources(resources: Dictionary) -> String:
	if resources.is_empty():
		return "nothing"
	var lines: PackedStringArray = []
	for id in resources:
		lines.append("%s x%d" % [id, resources[id]])
	return "\n".join(lines)


# ---------------------------------------------------------------------------
# Dialog
# ---------------------------------------------------------------------------

## One reusable message box. options: [{ "text": String, "action": Callable }]
func _show_dialog(title: String, body: String, options: Array[Dictionary]) -> void:
	dialog_title.text = title
	dialog_body.text = body
	for child in dialog_buttons.get_children():
		dialog_buttons.remove_child(child)
		child.queue_free()
	for option in options:
		var button := Button.new()
		button.text = option["text"]
		button.pressed.connect(_on_dialog_option.bind(option["action"]))
		dialog_buttons.add_child(button)
	dialog_layer.show()


func _on_dialog_option(action: Callable) -> void:
	dialog_layer.hide()
	if action.is_valid():
		action.call()
