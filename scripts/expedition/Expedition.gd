extends Control
## The expedition screen: the player sees the whole graph and picks the next node.
## Each node is then played: battle, camp, event... When the END node is reached
## (or the party is defeated) the expedition ends and the player goes back to the hub.
##
## All the nodes below use "Access as Unique Name" (see the scene tree in the docs).

const CAMP_HEAL_RATIO := 0.3  # share of max health recovered at a camp

## TEMPORARY, until battles give real loot: what a won battle gives.
const STUB_BATTLE_LOOT := {&"wood": 2}

@onready var map: ExpeditionMap = %Map
@onready var map_scroll: ScrollContainer = %MapScroll
@onready var title_label: Label = %TitleLabel
@onready var goal_label: Label = %GoalLabel
@onready var team_panel: Container = %TeamPanel
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

	if _run.current_node_id == &"":
		# A new run starts on the START node, which needs no resolution
		_run.enter_node(_expedition.get_start().id)
		_run.resolve_node()
	_refresh()

	# A run loaded in the middle of a node resumes it
	if not _run.node_resolved:
		_play_node(_expedition.get_node_by_id(_run.current_node_id))


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
	_refresh()
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
			_finish(true)
		_:
			_resolve()


## The node is done: the player can pick the next one.
func _resolve() -> void:
	_run.resolve_node()
	_refresh()


## STUB: the real battle comes with phase 4 (change to the battle scene with the
## encounter of the node, and come back here with the result).
func _start_battle(node: ExpeditionNode) -> void:
	_show_dialog(node.title, "Battle (not implemented yet).\nChoose the result:", [
		{"text": "Victory", "action": _on_battle_finished.bind(true)},
		{"text": "Defeat", "action": _on_battle_finished.bind(false)},
	])


func _on_battle_finished(victory: bool) -> void:
	if not victory:
		_finish(false)
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


## Ends the expedition: loot goes into the profile (half of it after a defeat).
func _finish(victory: bool) -> void:
	var kept := GameState.end_run(victory)
	var report := "Loot kept:\n"
	if kept.is_empty():
		report += "nothing"
	for id in kept:
		report += "%s x%d\n" % [id, kept[id]]
	if not victory:
		report = "The party was defeated and only recovered part of its loot.\n\n" + report

	_show_dialog("Expedition complete" if victory else "Expedition failed", report.strip_edges(),
		[{"text": "Return to the hub", "action": SceneManager.go_to.bind(&"hub")}])
	_refresh_team()


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
	action.call()
