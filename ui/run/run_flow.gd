class_name RunFlow
extends Control
## One run of the game, from the draft to the end:
##
##   new run -> squad draft (seeded) -> overworld -> attack or forced defense
##   -> battle screen -> result back to the map -> post-fight readout -> map
##
## The overworld is handed real contracts implementations: BotSquadProvider
## over the drafted bots, and a RunFightService that plays fights on the
## battle screen and applies PostFight to the bots when each one ends. The
## map code does not know any of this.
##
## Save and load go through RunSave, so a save holds the bots as well as the
## map. F3 on the battle screen shows the debug overlay (hidden by default).
##
## Run data: every run has its own folder (RunFolder) with its save, its
## journal and its F8 reports. A RunRecorder writes the journal of every
## draft pick, map action, battle command and fight, with state snapshots,
## and keeps the folder's summary. The run autosaves at the map start, after
## each fight and at each act change (data/run/run_data.json). Only the bots
## picked in the draft are kept. F8 pauses and opens the feedback form
## (FeedbackForm, FeedbackReport); the map gets a RUN FOLDER button beside NEW RUN.
##
## Variants: F4 opens the variant switchboard (ui/dev/) over the game, and a
## corner label lists the active non-default choices. A new run reads the
## draft rule and the act maps from it; each fight reads the fight-side
## choices when it starts (RunFightService). The campaign's choices
## (CampaignVariants) are read from the same file: squad-size by the draft,
## the other next-run ones when the map starts a run, grid-cost-owner when
## each fight starts. Selecting a region on the map makes it the
## auto-expansion focus.
##
## Run over (R2-A): when the run ends (every region lost, the act's loss
## limit, or the boss fight), the map's end message leads to the run-over
## screen (ui/main/run_over_screen.gd) with the folder's summary; MAIN MENU
## emits exit_requested (the main menu closes the flow), or starts a new run
## when nothing listens.
##
## Every change of screen plays the ScreenTransition wipe over the swap. The
## readout counts up; CONTINUE skips the count-up first, then goes back to
## the map.

const DRAFT_SCENE := preload("res://ui/draft/draft_screen.tscn")
const OVERWORLD_SCENE := preload("res://ui/overworld/overworld.tscn")
const READOUT_SCENE := preload("res://ui/post_fight/post_fight_readout.tscn")

const NO_SEED := -1
const CONTINUE_SIZE := Vector2(220, 48)
const SCREEN_MARGIN := 24.0
const LABEL_MARGIN := 6.0
## Above every screen of the run, so the label and F4 screen always show.
const VARIANT_LAYER := 50

enum Stage { DRAFT, MAP, FIGHT, POST_FIGHT }

signal stage_changed(stage: Stage)
## The player left a finished run for the main menu.
signal exit_requested

## Set before the flow enters the tree. NO_SEED draws a new seed per run.
@export var run_seed := NO_SEED
## Dev option: let the player choose act 1's start. In normal play the start
## is picked from the run seed and no choice is shown.
@export var choose_start := false
## Plays fights with AutoFightService instead of the battle screen.
@export var auto_fights := false
## Dev option: the map variant for each act, by act index ("" for the act's
## default). The dev menu sets it; see data/tuning/acts.json for the ids.
@export var map_variants: PackedStringArray = []
## The player's variant choices; tests point it elsewhere.
var variants_path := FightVariants.USER_PATH
## Battle screen tuning; null means data/ui/fight_screen.json.
var fight_screen_tuning: FightScreenTuning
## Set on the overworld when it is made, as its own exports: tests use them.
var region_file := ""
## Where run folders go; "" means data/run/run_data.json's runs_folder. Tests
## point it elsewhere.
var runs_root := ""
## Set before the flow enters the tree: continue the run in this folder
## instead of starting a new one.
var start_dir := ""
## Opens a folder in the system file browser; tests replace it.
var folder_opener: Callable = func(path: String) -> void: OS.shell_open(path)
var run_settings := RunDataSettings.load_default()

var stage := Stage.DRAFT
## The seed this run's draft came from.
var current_seed := 0
## This run's folder.
var run_dir := ""
## Writes this run's journal and summary.
var recorder: RunRecorder
var squad: BotSquad
var ledger: SkillUseLedger
var fight_service: RunFightService

var draft_screen: DraftScreen
## The overworld screen (ui/overworld/overworld.gd), or null during the draft.
var overworld: Control
## The battle screen of the fight in progress, or null.
var battle_screen: BattleScreen
var debug_overlay: DebugOverlay
## The post-fight readout while it shows, or null.
var readout: Control
var continue_button: Button
## The switchboard as it stood when this run began: its draft rule and act
## maps hold for the whole run.
var run_board: Switchboard
## The F4 switchboard while it shows, or null.
var switchboard_screen: SwitchboardScreen
var variant_label: VariantLabel
## The wipe between screens.
var transition: ScreenTransition
var _variant_layer: CanvasLayer
## The F8 form while it shows, or null.
var feedback_form: FeedbackForm
## The run-over screen once the run has ended, or null.
var run_over_screen: RunOverScreen
## The folder of the last F8 report written.
var last_report_dir := ""
## The map's RUN FOLDER button, in the row with WAIT, SAVE, LOAD and NEW RUN.
var folder_button: Button
var _screenshot: Image
var _loading := false
var _last_act := -1


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = ScreenTheme.theme()
	transition = ScreenTransition.new()
	add_child(transition)
	_variant_layer = CanvasLayer.new()
	_variant_layer.name = "VariantLayer"
	_variant_layer.layer = VARIANT_LAYER
	add_child(_variant_layer)
	variant_label = VariantLabel.new()
	_variant_layer.add_child(variant_label)
	variant_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, int(LABEL_MARGIN))
	variant_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	get_tree().node_added.connect(_on_node_added)
	stage_changed.connect(func(s: Stage) -> void: MusicDirector.follow_stage(Stage.keys()[s]))
	if start_dir.is_empty() or not continue_run(start_dir):
		new_run()


func _exit_tree() -> void:
	if recorder != null:
		recorder.finish()
	if get_tree().paused and feedback_form != null:
		get_tree().paused = false
	# The campaign layer reads choices from this path; stop pointing it here.
	if CampaignVariants.user_path == variants_path:
		CampaignVariants.user_path = ""
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F4:
		toggle_switchboard()
		get_viewport().set_input_as_handled()
	elif key != null and key.pressed and not key.echo and key.keycode == KEY_F8:
		open_feedback()
		get_viewport().set_input_as_handled()


## Shows or hides the variant switchboard over the game.
func toggle_switchboard() -> void:
	if switchboard_screen != null:
		_free(switchboard_screen)
		switchboard_screen = null
		return
	switchboard_screen = SwitchboardScreen.new()
	switchboard_screen.name = "SwitchboardScreen"
	switchboard_screen.board = Switchboard.load_board(variants_path)
	switchboard_screen.closable = true
	switchboard_screen.changed.connect(func() -> void: variant_label.show_board(switchboard_screen.board))
	switchboard_screen.closed.connect(toggle_switchboard)
	_variant_layer.add_child(switchboard_screen)
	_variant_layer.move_child(variant_label, -1)


## Drops the run in progress and opens the draft for a new one.
func new_run() -> void:
	transition.cover()
	_close_all()
	_set_squad(null, null)
	current_seed = run_seed if run_seed != NO_SEED else randi()
	CampaignVariants.user_path = variants_path
	run_board = Switchboard.load_board(variants_path)
	variant_label.show_board(run_board)
	var bot_tuning := run_bot_tuning()
	_begin_recording(RunFolder.create(runs_folder(), current_seed))
	recorder.start(run_dir, current_seed, {
		"variants": Dictionary(run_board.choices),
		"draft_rule": bot_tuning.draft_rule,
		"draft_size": bot_tuning.draft_size,
		"squad_size": bot_tuning.squad_size,
		"act_variants": Array(run_map_variants()),
		"region_file": region_file,
		"choose_start": choose_start,
		"auto_fights": auto_fights,
	})
	draft_screen = DRAFT_SCENE.instantiate()
	draft_screen.draft_seed = current_seed
	draft_screen.bot_tuning = bot_tuning
	draft_screen.squad_chosen.connect(_on_squad_chosen)
	add_child(draft_screen)
	draft_screen.start_button.text = "DEPLOY SQUAD"
	recorder.draft_open(draft_screen.picker.bots())
	_set_stage(Stage.DRAFT)


## Continues the run in folder `dir` from its save: a new session of the same
## journal. False, with nothing changed, if the folder has no usable save.
func continue_run(dir: String) -> bool:
	if RunSave.load_file(RunFolder.save_path(dir)) == null:
		return false
	transition.cover()
	_close_all()
	CampaignVariants.user_path = variants_path
	run_board = Switchboard.load_board(variants_path)
	variant_label.show_board(run_board)
	_begin_recording(dir)
	recorder.resume(dir)
	return load_run()


## The folder this flow's run folders go in.
func runs_folder() -> String:
	return runs_root if not runs_root.is_empty() else run_settings.runs_folder


## Opens this run's folder in the system file browser.
func open_run_folder() -> void:
	if not run_dir.is_empty():
		folder_opener.call(ProjectSettings.globalize_path(run_dir))


func _begin_recording(dir: String) -> void:
	if recorder != null:
		recorder.finish()
	run_dir = dir
	recorder = RunRecorder.new()
	recorder.squad = squad
	recorder.ledger = ledger
	recorder.auto_fights = auto_fights
	var path := variants_path
	recorder.fight_variants_source = func() -> FightVariants: return FightVariants.load_active(path)
	recorder.campaign_variants_source = func() -> CampaignVariants: return CampaignVariants.load_active(path)
	recorder.fight_seed_source = func(request: FightRequest) -> int:
		return fight_service.inner.seed_for(request) if fight_service != null and fight_service.inner.has_method("seed_for") else 0
	recorder.last_fight_source = func() -> Fight:
		return fight_service.inner.get("last_fight") as Fight if fight_service != null else null
	recorder.snapshot_written.connect(_on_snapshot_written)
	recorder.run_ended.connect(func(_won: bool) -> void: _autosave())


func _set_squad(p_squad: BotSquad, p_ledger: SkillUseLedger) -> void:
	squad = p_squad
	ledger = p_ledger
	if recorder != null:
		recorder.squad = squad
		recorder.ledger = ledger


## Takes the drafted squad to the map, where the start choice opens.
func start_map(p_squad: BotSquad, p_ledger: SkillUseLedger) -> void:
	_open_map(p_squad, p_ledger)
	if recorder != null and overworld.campaign != null:
		recorder.map_start(overworld.campaign)
		recorder.set_act_name(overworld.plan.act_name(overworld.campaign.state.act))
		if run_settings.autosave_at_map_start:
			_autosave()


func _open_map(p_squad: BotSquad, p_ledger: SkillUseLedger) -> void:
	transition.cover()
	_close_all()
	_set_squad(p_squad, p_ledger)
	_last_act = -1
	_open_overworld()
	_set_stage(Stage.MAP)


## Closes the post-fight readout and shows the map again.
func continue_to_map() -> void:
	if readout == null:
		return
	transition.cover()
	_free(readout)
	readout = null
	continue_button = null
	overworld.visible = true
	_set_stage(Stage.MAP)


## Saves the map, the bots and the banked skill uses in one file: this run's
## save in its folder unless `path` names another. An autosave (`auto`)
## writes nothing in the map's log.
func save_run(path := "", auto := false) -> Error:
	if overworld == null or overworld.campaign == null or overworld.campaign.fighting:
		return ERR_BUSY
	if path.is_empty():
		if run_dir.is_empty():
			return ERR_UNCONFIGURED
		path = RunFolder.save_path(run_dir)
	var error := RunSave.make(current_seed, squad, ledger, overworld.campaign.state).save_file(path)
	if not auto:
		overworld.log_event("Run saved." if error == OK else "Could not save the run (%s)." % error_string(error))
	if error == OK and recorder != null:
		recorder.action(RunJournal.ACTION_SAVE, "", {"auto": auto, "file": path.get_file()})
	return error


## Continues the run saved at `path` (this run's save when empty): the same
## bots, map state and act. False, with the current run kept, if there is no
## usable save.
func load_run(path := "") -> bool:
	if path.is_empty() and not run_dir.is_empty():
		path = RunFolder.save_path(run_dir)
	var save := RunSave.load_file(path)
	if save == null:
		if overworld != null:
			overworld.log_event("No saved run.")
		return false
	# Runs saved before run folders kept the bench; a run keeps its squad only.
	save.squad = save.squad.to_fielded_squad()
	_loading = true
	var loaded := _load_save(save)
	_loading = false
	if loaded and recorder != null:
		_last_act = overworld.campaign.state.act
		recorder.action(RunJournal.ACTION_LOAD, "", {"file": path.get_file()})
		recorder.snapshot(RunJournal.SNAPSHOT_LOAD)
		recorder.set_act_name(overworld.plan.act_name(overworld.campaign.state.act))
	return loaded


func _load_save(save: RunSave) -> bool:
	if overworld == null:
		current_seed = save.run_seed
		_open_map(save.squad, save.ledger)
		if overworld.load_state(save.run_state()):
			return true
		new_run()
		return false
	var kept := [squad, ledger, fight_service, overworld.squad_provider, overworld.fight_service]
	_set_squad(save.squad, save.ledger)
	_hand_services_to(overworld)
	if not overworld.load_state(save.run_state()):
		_set_squad(kept[0], kept[1])
		fight_service = kept[2]
		overworld.squad_provider = kept[3]
		overworld.fight_service = kept[4]
		return false
	current_seed = save.run_seed
	overworld.odds.run_seed = current_seed
	_close_readout_and_show_map()
	return true


## TODO(decision: autosave): the run saves itself at the map start, after
## every fight and at every act change (data/run/run_data.json "autosave"), so
## Continue and the F8 report always have a recent save. There is one save per
## run; SAVE on the map writes the same file.
func _autosave() -> void:
	save_run("", true)


func _on_snapshot_written(reason: String) -> void:
	if (reason == RunJournal.SNAPSHOT_FIGHT and run_settings.autosave_after_fight) \
			or (reason == RunJournal.SNAPSHOT_ACT and run_settings.autosave_after_act):
		_autosave()


## Bot tuning for this run's draft: data/bot_data/ with the switchboard's
## draft rule and squad size.
func run_bot_tuning() -> BotTuning:
	var tuning := BotTuning.load_default()
	var rule := run_board.draft_rule() if run_board != null else ""
	if rule in BotTuning.DRAFT_RULES:
		tuning.draft_rule = rule
	var sizes := CampaignVariants.load_active(variants_path).squad_sizes()
	if not sizes.is_empty():
		tuning.draft_size = sizes.draft_size
		tuning.squad_size = sizes.squad_size
	return tuning


## The map variant per act this run plays: map_variants when set (the dev
## menu, tests), else the switchboard's act maps.
func run_map_variants() -> PackedStringArray:
	if not map_variants.is_empty() or run_board == null:
		return map_variants
	return run_board.act_map_variants()


## The start this run's seed gives, one of `options`.
func seeded_start(options: Array) -> String:
	return options[posmod(current_seed, options.size())].id


## A run keeps only the bots picked in the draft, in pick order.
func _on_squad_chosen(_summaries: Array[SquadMemberSummary]) -> void:
	var picked := draft_screen.picker.squad.to_fielded_squad()
	if recorder != null:
		recorder.draft_done(picked.fielded_ids)
	start_map(picked, SkillUseLedger.new())


func _open_overworld() -> void:
	overworld = OVERWORLD_SCENE.instantiate()
	if not region_file.is_empty():
		overworld.region_file = region_file
	overworld.act_variants = run_map_variants()
	_hand_services_to(overworld)
	overworld.save_action = func() -> void: save_run()
	overworld.load_action = func() -> void: load_run()
	overworld.new_run_action = new_run
	overworld.run_over_action = show_run_over
	if not choose_start:
		overworld.start_picker = seeded_start
	overworld.campaign_started.connect(_on_campaign_started)
	add_child(overworld)
	overworld.odds.run_seed = current_seed
	_add_folder_button()


## RUN FOLDER beside the map's NEW RUN button, styled like it.
func _add_folder_button() -> void:
	var wait: Variant = overworld.get("_wait_button")
	if not wait is Button:
		return
	var row: Node = (wait as Button).get_parent()
	var last := row.get_child(row.get_child_count() - 1) as Button
	folder_button = last.duplicate(0) as Button if last != null else Button.new()
	folder_button.name = "OpenRunFolderButton"
	folder_button.text = "RUN FOLDER"
	folder_button.tooltip_text = "Open this run's folder: its save, journal and F8 reports."
	folder_button.pressed.connect(open_run_folder)
	row.add_child(folder_button)


## A new Campaign on the map: the next act after a zoom, or a load. The
## journal follows it; an act change gets its line, snapshot and autosave.
func _on_campaign_started(c: Campaign) -> void:
	if recorder == null:
		return
	var zoomed := not _loading and _last_act >= 0 and c.state.act > _last_act
	if zoomed:
		recorder.action(RunJournal.ACTION_ACT_ZOOM, "", {"to_act": c.state.act})
	recorder.watch_campaign(c)
	_last_act = c.state.act
	if zoomed:
		recorder.set_act_name(overworld.plan.act_name(c.state.act))
		recorder.snapshot(RunJournal.SNAPSHOT_ACT)


## Gives `screen` real contracts implementations over the current squad.
## They are read when its next Campaign is made.
func _hand_services_to(screen: Control) -> void:
	var inner: FightService
	if auto_fights:
		inner = AutoFightService.new()
	else:
		var scene_service := FightSceneService.new(self, fight_screen_tuning)
		scene_service.bot_source = func(id: String) -> Bot: return squad.get_bot(id) if squad != null else null
		scene_service.screen_opened.connect(_on_screen_opened)
		inner = scene_service
	fight_service = RunFightService.new(inner, squad, ledger)
	var path := variants_path
	fight_service.variants_source = func() -> FightVariants: return FightVariants.load_active(path)
	fight_service.campaign_variants_source = func() -> CampaignVariants: return CampaignVariants.load_active(path)
	fight_service.fight_reported.connect(_on_fight_reported)
	fight_service.finished.connect(_on_fight_finished)
	screen.squad_provider = BotSquadProvider.new(squad)
	screen.fight_service = fight_service


## A map view joining the tree (the overworld's, flat or globe): selecting a
## region on it makes that region the campaign's expansion focus.
func _on_node_added(node: Node) -> void:
	if node.has_signal("region_selected") and overworld != null and overworld.is_ancestor_of(node):
		node.connect("region_selected", _on_region_selected)


func _on_region_selected(region_id: String) -> void:
	if overworld != null and overworld.campaign != null:
		var before: String = overworld.campaign.state.focus_id
		overworld.campaign.set_focus(region_id)
		if recorder != null and overworld.campaign.state.focus_id != before:
			recorder.action(RunJournal.ACTION_FOCUS, region_id)


func _on_screen_opened(screen: BattleScreen) -> void:
	transition.cover()
	battle_screen = screen
	overworld.visible = false
	debug_overlay = DebugOverlay.new()
	debug_overlay.visible = false
	# Show the intents the screen telegraphs, which are what enemies do.
	debug_overlay.intent_source = func(f: Fight, unit: Combatant) -> String: return screen.telegraph.intent_text(f, unit.id)
	screen.add_child(debug_overlay)
	debug_overlay.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, int(SCREEN_MARGIN))
	debug_overlay.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	debug_overlay.fight = screen.fight
	if recorder != null:
		recorder.watch_battle(screen)
	_set_stage(Stage.FIGHT)


func _on_fight_reported(report: PostFightReport, _result: FightResult) -> void:
	transition.cover()
	battle_screen = null
	debug_overlay = null
	overworld.visible = false
	readout = READOUT_SCENE.instantiate()
	add_child(readout)
	readout.show_report(report)
	continue_button = Button.new()
	continue_button.name = "ContinueButton"
	continue_button.custom_minimum_size = CONTINUE_SIZE
	continue_button.pressed.connect(_on_continue_pressed)
	readout.tally_finished.connect(_label_continue)
	_label_continue()
	readout.add_child(continue_button)
	continue_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, int(SCREEN_MARGIN))
	continue_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	continue_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_set_stage(Stage.POST_FIGHT)


## During the count-up the button skips it; after, it goes back to the map.
func _on_continue_pressed() -> void:
	if readout != null and readout.is_tallying():
		readout.skip()
	else:
		SoundPlayer.fire(&"ui_confirm")
		continue_to_map()


func _label_continue() -> void:
	if continue_button != null:
		continue_button.text = "SKIP" if readout.is_tallying() else "BACK TO THE MAP"


## A fight with no report (a stub service) goes straight back to the map.
func _on_fight_finished(_result: FightResult) -> void:
	battle_screen = null
	debug_overlay = null
	if readout == null:
		_close_readout_and_show_map()


func _close_readout_and_show_map() -> void:
	if readout != null:
		continue_to_map()
		return
	if overworld != null:
		if not overworld.visible:
			transition.cover()
		overworld.visible = true
		_set_stage(Stage.MAP)


func _close_all() -> void:
	for node: Node in [draft_screen, overworld, readout, battle_screen, run_over_screen]:
		_free(node)
	run_over_screen = null
	draft_screen = null
	overworld = null
	folder_button = null
	readout = null
	continue_button = null
	battle_screen = null
	debug_overlay = null


func _set_stage(p_stage: Stage) -> void:
	stage = p_stage
	stage_changed.emit(stage)


# --- Run over ---------------------------------------------------------------------

## Shows the run-over screen over the map, from the run folder's summary.
func show_run_over() -> void:
	if run_over_screen != null:
		return
	transition.cover()
	if recorder != null:
		recorder.snapshot_summary()
	run_over_screen = RunOverScreen.new()
	run_over_screen.name = "RunOverScreen"
	run_over_screen.show_run(run_dir, RunFolder.read_summary(run_dir))
	run_over_screen.main_menu_requested.connect(leave_to_menu)
	run_over_screen.folder_requested.connect(open_run_folder)
	if overworld != null:
		overworld.visible = false
	add_child(run_over_screen)


## Leaves the finished run: back to the main menu when one is listening,
## otherwise a new run.
func leave_to_menu() -> void:
	if exit_requested.get_connections().is_empty():
		new_run()
	else:
		exit_requested.emit()


# --- F8 feedback ------------------------------------------------------------------

## Pauses the game and opens the feedback form, with a screenshot taken
## first. Does nothing while the form is already up or outside a run.
func open_feedback() -> void:
	if feedback_form != null or recorder == null or run_dir.is_empty():
		return
	# Headless runs render nothing to take.
	var texture := get_viewport().get_texture() if DisplayServer.get_name() != "headless" else null
	_screenshot = texture.get_image() if texture != null else null
	# The report carries the save as it is now, when the map allows saving.
	if stage == Stage.MAP:
		_autosave()
	recorder.pause()
	get_tree().paused = true
	feedback_form = FeedbackForm.new()
	feedback_form.name = "FeedbackForm"
	feedback_form.settings = run_settings
	feedback_form.context_text = "Run %s · %s" % [run_dir.get_file(), screen_name()]
	feedback_form.submitted.connect(write_feedback)
	feedback_form.cancelled.connect(close_feedback)
	feedback_form.open_folder_requested.connect(open_run_folder)
	_variant_layer.add_child(feedback_form)


## Writes the F8 report and closes the form. Returns the report's folder.
func write_feedback(note: String, category: String, rating: int) -> String:
	var info := {
		"note": note,
		"category": category,
		"rating": rating,
		"stage": Stage.keys()[stage].to_lower(),
		"screen": screen_name(),
		"run": run_dir.get_file(),
		"seed": current_seed,
		"variants": Dictionary(Switchboard.load_board(variants_path).choices),
		"time": Time.get_datetime_string_from_system(false, true),
		"play_s": snappedf(recorder.play_seconds(), 0.001),
	}
	if overworld != null and overworld.campaign != null:
		info["act"] = overworld.campaign.state.act + 1
		info["act_name"] = overworld.plan.act_name(overworld.campaign.state.act)
		info["day"] = overworld.campaign.day()
	last_report_dir = FeedbackReport.write(RunFolder.reports_path(run_dir), info, _screenshot,
		RunFolder.save_path(run_dir), RunFolder.journal_path(run_dir))
	recorder.feedback(last_report_dir.get_file(), category, rating)
	close_feedback()
	if overworld != null:
		overworld.log_event("Feedback saved to reports/%s." % last_report_dir.get_file())
	return last_report_dir


## Closes the F8 form and unpauses.
func close_feedback() -> void:
	if feedback_form != null:
		_free(feedback_form)
		feedback_form = null
	_screenshot = null
	get_tree().paused = false
	if recorder != null:
		recorder.unpause()


## Which screen is up, for the F8 report: "map", "map: <message title>",
## "battle: attack <region>", "post-fight readout", "draft".
func screen_name() -> String:
	var text := ""
	match stage:
		Stage.DRAFT:
			text = "draft"
		Stage.FIGHT:
			text = "battle"
			if battle_screen != null:
				text += ": %s %s" % [FightRequest.Kind.keys()[battle_screen.fight.request.kind].to_lower(),
					battle_screen.fight.request.territory_id]
		Stage.POST_FIGHT:
			text = "post-fight readout"
		_:
			text = "map"
			var modal: Variant = overworld.get("_modal") if overworld != null else null
			var title: Variant = overworld.get("_modal_title") if overworld != null else null
			if modal is Control and (modal as Control).visible and title is Label:
				text += ": %s" % (title as Label).text
			if overworld != null and overworld.get("zooming"):
				text += " (act zoom)"
	if switchboard_screen != null:
		text += " + F4 switchboard"
	return text


static func _free(node: Node) -> void:
	if node != null and is_instance_valid(node):
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		node.queue_free()
