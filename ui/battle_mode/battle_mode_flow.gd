class_name BattleModeFlow
extends Control
## Battle Mode on screen: setup (length and squad), the draft when chosen,
## then fight after fight on the battle screen with the post-fight readout
## between, and the end-of-run summary. The loop is BattleModeRun
## (fight/battle_mode/), the same one tools/battle_mode_sim.gd plays
## headless, so played and simulated runs report the same numbers.
##
## Under the readout a bar shows this fight's numbers (BattleFightLine) and
## what comes next. When the run ends, its fights and summary are appended to
## the CSV in user://battle_mode/ (never the save or the settings).
##
## Saving: TODO(decision: battle-mode-save). Battle Mode keeps no save; leaving
## ends the run (its fights so far still go to the CSV). Esc opens the Esc
## menu (PauseMenu) on the draft, battle and readout, which asks first; on the
## setup and summary screens Esc goes straight home.

signal exit_requested

enum Stage { SETUP, DRAFT, FIGHT, READOUT, OVER }

const DRAFT_SCENE := preload("res://ui/draft/draft_screen.tscn")
const BATTLE_SCENE := preload("res://ui/fight/battle_screen.tscn")
const READOUT_SCENE := preload("res://ui/post_fight/post_fight_readout.tscn")
const NO_SEED := -1
const CONTINUE_SIZE := Vector2(240, 48)
## Above every screen of the flow, for the Esc menu.
const MENU_LAYER := 50
const LEAVE_TITLE := "Leave Battle Mode?"
const LEAVE_BODY := "Battle Mode keeps no save: this run ends here. The fights so far still go to the CSV."

signal stage_changed(stage: Stage)

var stage := Stage.SETUP
var tuning: BattleModeTuning
## The run seed; NO_SEED draws a new one for each run. Tests set it.
var run_seed := NO_SEED
## The battle screen's tuning; null is data/ui/fight_screen.json. Tests speed it up.
var fight_screen_tuning: FightScreenTuning
## Where the CSV goes; "" is data/battle_mode/'s csv_folder.
var csv_folder := ""
## The fight switches each run plays with.
var variants_source: Callable = func() -> FightVariants: return FightVariants.load_active()

var run: BattleModeRun
var setup_screen: BattleModeSetup
var draft_screen: DraftScreen
var battle_screen: BattleScreen
var readout: Control
var readout_page: VBoxContainer
var continue_button: Button
var readout_home_button: ActionButton
var summary_screen: BattleModeSummary
var pause_menu: PauseMenu
var transition: ScreenTransition
## The last run's CSV write: OK, an error, or ERR_UNCONFIGURED before any.
var csv_result := ERR_UNCONFIGURED
var _layer: CanvasLayer
var _length_id := ""
var _squad_id := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = ScreenTheme.theme()
	if tuning == null:
		tuning = BattleModeTuning.load_default()
	transition = ScreenTransition.new()
	add_child(transition)
	_layer = CanvasLayer.new()
	_layer.name = "MenuLayer"
	_layer.layer = MENU_LAYER
	add_child(_layer)
	show_setup()


func _exit_tree() -> void:
	if pause_menu != null and get_tree().paused:
		get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel") or event.is_echo():
		return
	if stage == Stage.SETUP or stage == Stage.OVER:
		leave()
		get_viewport().set_input_as_handled()
	elif open_pause_menu() != null:
		get_viewport().set_input_as_handled()


# --- Setup and draft ------------------------------------------------------------------

func show_setup() -> void:
	transition.cover()
	_close_all()
	setup_screen = BattleModeSetup.new()
	setup_screen.name = "BattleModeSetup"
	setup_screen.tuning = tuning
	if not _length_id.is_empty():
		setup_screen.length_id = _length_id
		setup_screen.squad_id = _squad_id
	setup_screen.started.connect(start)
	setup_screen.home_requested.connect(leave)
	add_child(setup_screen)
	_set_stage(Stage.SETUP)
	if MusicDirector.current != null:
		MusicDirector.current.play_context(MusicDirector.MENU)


## Starts a run of `length_id` with a preset squad, or opens the draft for
## BattleModeSetup.DRAFT.
func start(length_id: String, squad_id: String) -> void:
	_length_id = length_id
	_squad_id = squad_id
	if squad_id == BattleModeSetup.DRAFT:
		open_draft()
		return
	begin(BattleModeRun.preset_squad(squad_id, tuning), squad_id)


func open_draft() -> void:
	transition.cover()
	_close_all()
	draft_screen = DRAFT_SCENE.instantiate()
	draft_screen.draft_seed = _seed()
	draft_screen.combat_tuning = CombatTuning.load_default().with_variants(variants_source.call())
	draft_screen.squad_chosen.connect(func(_summaries: Array[SquadMemberSummary]) -> void:
		begin(draft_screen.picker.squad.to_fielded_squad(), "draft"))
	add_child(draft_screen)
	draft_screen.start_button.text = "START BATTLE MODE"
	_set_stage(Stage.DRAFT)


## Starts the run with `squad` and fights its first battle.
func begin(squad: BotSquad, squad_label: String) -> void:
	run = BattleModeRun.create(squad, _length_id, _seed(), variants_source.call(), tuning)
	run.squad_label = squad_label
	run.policy = "player"
	next_fight()


func _seed() -> int:
	return run_seed if run_seed != NO_SEED else randi() & 0x7fffffff


# --- Fights --------------------------------------------------------------------------

## Opens the run's next fight on the battle screen.
func next_fight() -> void:
	transition.cover()
	_close_all()
	battle_screen = BATTLE_SCENE.instantiate()
	battle_screen.name = "BattleScreen"
	battle_screen.setup(run.next_request(), run.fight_seed(), fight_screen_tuning, run.combat_tuning, run.next_enemy_table())
	var squad := run.squad
	battle_screen.bot_source = func(id: String) -> Bot: return squad.get_bot(id)
	var fight := battle_screen.fight
	run.watch(fight)
	var rec := run.recorder
	battle_screen.handler.action_resolved.connect(func(_id: String, _tag: String) -> void: rec.after_action(fight))
	battle_screen.fight_finished.connect(_on_fight_finished, CONNECT_ONE_SHOT)
	if MusicDirector.current != null:
		MusicDirector.current.boss_battle = run.encounter.kind == BattleEncounter.Kind.BOSS
	add_child(battle_screen)
	battle_screen.show_home_button(go_home)
	_set_stage(Stage.FIGHT)
	MusicDirector.follow_stage("FIGHT")


func _on_fight_finished(_result: FightResult) -> void:
	var done := battle_screen
	var record := run.finish_fight(done.fight)
	battle_screen = null
	if run.is_over():
		_write_csv()
	# The last action may resolve inside the screen's own frame.
	await get_tree().process_frame
	if is_instance_valid(done):
		done.queue_free()
	show_readout(record)


# --- Readout ---------------------------------------------------------------------------

## The post-fight readout (growth) over a bar with this fight's numbers and
## what comes next.
func show_readout(record: BattleFightRecord) -> void:
	transition.cover()
	_close_all()
	readout_page = VBoxContainer.new()
	readout_page.name = "ReadoutPage"
	readout_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	readout_page.add_theme_constant_override("separation", 0)
	add_child(readout_page)
	readout = READOUT_SCENE.instantiate()
	readout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	readout_page.add_child(readout)
	if run.last_report != null:
		readout.show_report(run.last_report)
	var bar := PanelContainer.new()
	bar.name = "BattleModeBar"
	var style := UiStyle.panel("plain")
	style.set_content_margin_all(UiStyle.space("m"))
	bar.add_theme_stylebox_override("panel", style)
	readout_page.add_child(bar)
	var row := UiStyle.row("m")
	bar.add_child(row)
	readout_home_button = ActionButton.make("action_home", "Home")
	readout_home_button.name = "HomeButton"
	readout_home_button.pressed.connect(go_home)
	row.add_child(readout_home_button)
	var info := UiStyle.column("xs")
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var head := UiStyle.row("s")
	info.add_child(head)
	head.add_child(UiStyle.label(_fight_title(record.fight_number, record.kind), "title"))
	if record.kind != "normal":
		head.add_child(Flag.of(record.kind))
	head.add_child(UiStyle.spring())
	head.add_child(UiStyle.label(_next_text(), "text_quiet"))
	info.add_child(BattleFightLine.make(record, run.action_name, tuning.dominant_share_percent))
	continue_button = Button.new()
	continue_button.name = "ContinueButton"
	continue_button.custom_minimum_size = CONTINUE_SIZE
	continue_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	continue_button.pressed.connect(_on_continue_pressed)
	readout.tally_finished.connect(_label_continue)
	row.add_child(continue_button)
	_label_continue()
	_set_stage(Stage.READOUT)
	MusicDirector.follow_stage("POST_FIGHT")


func _fight_title(n: int, kind: String) -> String:
	var of := "" if run.length.is_endless() else " of %d" % run.length.fights
	return "Fight %d%s%s" % [n, of, "" if kind == "normal" else " · " + kind.capitalize()]


## What CONTINUE leads to, in words.
func _next_text() -> String:
	if run.is_over():
		return "Run cleared" if run.is_cleared() else "The squad is down"
	var e := run.next_encounter()
	var kinds := e.distinct_types()
	return "Next: %s · %d enem%s, %d kind%s" % [
		_fight_title(e.fight_number, BattleEncounter.kind_name(e.kind)), e.enemy_ids.size(),
		"y" if e.enemy_ids.size() == 1 else "ies", kinds, "" if kinds == 1 else "s"]


func _label_continue() -> void:
	if continue_button == null:
		return
	if readout.is_tallying():
		continue_button.text = "SKIP"
	else:
		continue_button.text = "SEE THE RUN" if run.is_over() else "NEXT FIGHT"


func _on_continue_pressed() -> void:
	if readout != null and readout.is_tallying():
		readout.skip()
		return
	SoundPlayer.fire(&"ui_confirm")
	if run.is_over():
		show_summary()
	else:
		next_fight()


# --- End ----------------------------------------------------------------------------

func show_summary() -> void:
	transition.cover()
	_close_all()
	summary_screen = BattleModeSummary.new()
	summary_screen.name = "BattleModeSummary"
	summary_screen.show_summary(run.summary(), run.action_name,
		ProjectSettings.globalize_path(_csv_dir().path_join("runs.csv")) if csv_result == OK else "")
	summary_screen.again_requested.connect(show_setup)
	summary_screen.home_requested.connect(leave)
	add_child(summary_screen)
	_set_stage(Stage.OVER)
	if MusicDirector.current != null:
		MusicDirector.current.play_context(MusicDirector.MENU)


func _csv_dir() -> String:
	return csv_folder if not csv_folder.is_empty() else tuning.csv_folder


## Appends the run's fights to the CSV once, with the time in the run id so
## replays of a seed stay apart.
func _write_csv() -> void:
	if run == null or run.records.is_empty() or csv_result == OK:
		return
	var id := "%s-%s" % [run.run_id(), Time.get_datetime_string_from_system(false, true).replace(" ", "T")]
	csv_result = run.write_csv(_csv_dir(), id)


# --- Leaving -------------------------------------------------------------------------

## Pauses under the Esc menu (draft, battle, readout). Null when it cannot open.
func open_pause_menu() -> PauseMenu:
	if pause_menu != null:
		return pause_menu
	if get_tree().paused:
		return null
	pause_menu = PauseMenu.new()
	pause_menu.name = "PauseMenu"
	pause_menu.note_text = "Main menu ends this Battle Mode run."
	pause_menu.confirm_title = LEAVE_TITLE
	pause_menu.confirm_body = LEAVE_BODY
	pause_menu.confirm_leave_text = "Leave"
	pause_menu.resumed.connect(close_pause_menu)
	pause_menu.home_requested.connect(leave)
	_layer.add_child(pause_menu)
	get_tree().paused = true
	return pause_menu


func close_pause_menu() -> void:
	if pause_menu == null:
		return
	pause_menu.queue_free()
	pause_menu = null
	get_tree().paused = false


## Home: straight out on setup and summary, else the Esc menu's confirm step.
func go_home() -> void:
	if stage == Stage.SETUP or stage == Stage.OVER:
		leave()
		return
	var menu := open_pause_menu()
	if menu != null:
		menu.request_home()


## Ends the run (its fights so far go to the CSV) and asks to leave.
func leave() -> void:
	close_pause_menu()
	if run != null and not run.is_over():
		run.abandon()
		_write_csv()
	exit_requested.emit()


func _close_all() -> void:
	for node: Node in [setup_screen, draft_screen, battle_screen, readout_page, summary_screen]:
		if node != null and is_instance_valid(node):
			remove_child(node)
			node.queue_free()
	setup_screen = null
	draft_screen = null
	battle_screen = null
	readout_page = null
	readout = null
	continue_button = null
	readout_home_button = null
	summary_screen = null


func _set_stage(p_stage: Stage) -> void:
	if p_stage == Stage.SETUP:
		run = null
		csv_result = ERR_UNCONFIGURED
	stage = p_stage
	stage_changed.emit(stage)
