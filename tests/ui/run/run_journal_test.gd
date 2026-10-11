extends GdUnitTestSuite
## Run data end to end: a run played through RunFlow writes its folder, its
## journal and its summary; the headless replay (tools/run_replay.gd)
## re-plays the journal and every snapshot matches; F8 writes a report.

const SCENE := preload("res://ui/run/run_flow.tscn")
const Helpers := preload("res://tests/ui/fight/fight_ui_helpers.gd")
const RunData := preload("res://tests/ui/run/run_data_helpers.gd")
const RUNS_ROOT := "user://test_runs/run_journal_test"
const VARIANTS := "user://test_runs/run_journal_test_variants.json"
const RUN_SEED := 13

var _flow: RunFlow
var _opened: Array[String] = []


func after_test() -> void:
	get_tree().paused = false
	RunData.remove_tree(RUNS_ROOT)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(VARIANTS))
	CampaignVariants.user_path = ""


func _open(auto_fights := false, start_dir := "") -> void:
	_flow = SCENE.instantiate()
	_flow.run_seed = RUN_SEED
	_flow.auto_fights = auto_fights
	_flow.variants_path = VARIANTS
	_flow.fight_screen_tuning = Helpers.fast_tuning()
	_flow.runs_root = RUNS_ROOT
	_flow.start_dir = start_dir
	_flow.folder_opener = func(path: String) -> void: _opened.append(path)
	var runner := scene_runner(auto_free(_flow))
	await runner.simulate_frames(2)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _draft() -> void:
	var screen := _flow.draft_screen
	for i in screen.picker.squad_size():
		screen.cards[screen.picker.bots()[i].id].pressed.emit()
	screen.start_button.pressed.emit()
	await _frames(1)


func _adjacent_target() -> String:
	var campaign: Campaign = _flow.overworld.campaign
	var best: MapRegion = null
	for region in campaign.map.regions:
		if campaign.standing(region.id) == Campaign.Standing.IN_RANGE and (best == null or region.defense < best.defense):
			best = region
	return best.id


func _await_stage(stage: RunFlow.Stage) -> void:
	var guard := 0
	while _flow.stage != stage and guard < 60:
		await _frames(1)
		guard += 1


func _journal() -> Array[Dictionary]:
	return RunJournal.read_file(RunFolder.journal_path(_flow.run_dir))


func _kinds(lines: Array[Dictionary]) -> Array:
	return lines.map(func(l: Dictionary) -> String: return str(l.kind))


func _replay(lines: Array[Dictionary]) -> RunReplay:
	var replay := RunReplay.new(lines)
	await replay.run()
	return replay


## Plays one fight on the battle screen by mouse, with a look at another bot,
## a cancel and a refused command along the way, then goes back to the map.
func _play_battle_by_mouse() -> void:
	var screen := _flow.battle_screen
	var fight := screen.fight
	var looked := false
	var guard := 0
	while not fight.is_over() and guard < 2000:
		guard += 1
		if not screen.handler.is_player_turn():
			await _frames(1)
			continue
		if not looked:
			looked = true
			for c in fight.living(Combatant.Side.PLAYER):
				if c != screen.handler.actor():
					screen.send(FightCommand.select_bot(c.id))
					screen.send(FightCommand.select_skill("strike"))  # refused: not that bot's turn
					screen.send(FightCommand.cancel())
					break
		Helpers.play_support_turn_by_mouse(screen)
	await _await_stage(RunFlow.Stage.POST_FIGHT)
	_flow.continue_to_map()
	await _frames(1)


func _close_modal() -> void:
	var overworld: Control = _flow.overworld
	if overworld._modal.visible and overworld._modal_buttons.get_child_count() > 0:
		(overworld._modal_buttons.get_child(0) as Button).pressed.emit()
	await _frames(1)


func test_a_new_run_gets_its_own_folder_with_journal_and_summary() -> void:
	await _open()
	assert_str(_flow.run_dir.get_base_dir()).is_equal(RUNS_ROOT)
	assert_bool(FileAccess.file_exists(RunFolder.journal_path(_flow.run_dir))).is_true()
	assert_bool(DirAccess.dir_exists_absolute(RunFolder.reports_path(_flow.run_dir))).is_true()
	assert_array(_kinds(_journal())).is_equal(["run_start", "session", "draft_open"])
	var first := _flow.run_dir
	_flow.new_run()
	# A second run with the same seed in the same minute never reuses the folder.
	assert_str(_flow.run_dir).is_not_equal(first)
	assert_str(_flow.run_dir).is_equal(first + "_2")
	assert_str(str(RunFolder.read_summary(first).stage)).is_equal("draft")


func test_a_run_keeps_only_the_drafted_bots() -> void:
	await _open(true)
	await _draft()
	assert_int(_flow.squad.bots.size()).is_equal(_flow.squad.squad_size)
	assert_array(_flow.squad.bots.map(func(b: Bot) -> String: return b.id)).is_equal(Array(_flow.squad.fielded_ids))
	# The autosave at the map start holds the squad only.
	var save := RunSave.load_file(RunFolder.save_path(_flow.run_dir))
	assert_object(save).is_not_null()
	assert_int(save.squad.bots.size()).is_equal(save.squad.squad_size)


func test_the_squad_size_variant_keeps_four_of_six() -> void:
	var board := Switchboard.load_board(VARIANTS)
	board.choose(CampaignVariants.SQUAD_SIZE, CampaignVariants.SQUAD_DRAFT6_FIELD4)
	board.save()
	await _open(true)
	assert_int(_flow.draft_screen.picker.bots().size()).is_equal(6)
	await _draft()
	assert_int(_flow.squad.bots.size()).is_equal(4)
	var start: Dictionary = _journal()[0]
	assert_int(int(start.squad_size)).is_equal(4)
	assert_int(int(start.draft_size)).is_equal(6)


func test_a_played_run_replays_exactly_from_its_journal() -> void:
	await _open()
	await _draft()
	var overworld: Control = _flow.overworld
	overworld._on_wait()
	var held: String = overworld.campaign.state.owned[0]
	overworld._on_reinforce(held)
	var target := _adjacent_target()
	_flow._on_region_selected(target)
	overworld._on_attack(target)
	await _frames(1)
	assert_int(_flow.stage).is_equal(RunFlow.Stage.FIGHT)
	await _play_battle_by_mouse()
	await _close_modal()
	assert_int(_flow.save_run()).is_equal(OK)
	overworld._on_wait()
	overworld._on_wait()
	assert_bool(_flow.load_run()).is_true()
	_flow.overworld._on_wait()

	var lines := _journal()
	var kinds := _kinds(lines)
	for kind in ["run_start", "session", "draft_open", "draft_done", "map_start", "snapshot", "action",
			"fight_start", "command", "resolved", "fight_end", "post_fight"]:
		assert_array(kinds).contains([kind])
	var actions := lines.filter(func(l: Dictionary) -> bool: return l.kind == "action").map(
		func(l: Dictionary) -> String: return str(l.action))
	assert_array(actions).contains(["wait", "reinforce", "focus", "attack", "save", "load"])
	var commands := lines.filter(func(l: Dictionary) -> bool: return l.kind == "command")
	assert_array(commands.map(func(l: Dictionary) -> String: return str(l.cmd))).contains(
		["select_bot", "select_skill", "select_target", "cancel"])
	assert_bool(commands.any(func(l: Dictionary) -> bool: return not str(l.problem).is_empty())).is_true()
	# Every line has its wall-clock and in-game time.
	for line in lines:
		assert_bool(line.has("ts") and line.has("unix") and line.has("play_s")).is_true()
	assert_bool(lines[-1].has("day") and lines[-1].has("act")).is_true()
	var post: Dictionary = lines.filter(func(l: Dictionary) -> bool: return l.kind == "post_fight")[0]
	assert_bool((post.changes as Dictionary).is_empty()).is_false()

	var replay := await _replay(lines)
	assert_array(replay.mismatches).is_empty()
	assert_bool(replay.is_match()).is_true()
	assert_int(replay.fights_played).is_equal(1)
	assert_int(replay.snapshots_checked).is_greater_equal(3)


func test_a_changed_journal_is_reported_as_a_mismatch() -> void:
	await _open(true)
	await _draft()
	_flow.overworld._on_attack(_adjacent_target())
	await _frames(3)
	var lines := _journal()
	for line in lines:
		if line.kind == "snapshot" and line.reason == "fight":
			line.state.grid = float(line.state.grid) + 5.0
	var replay := await _replay(lines)
	assert_bool(replay.is_match()).is_false()
	assert_str(replay.mismatches[0]).contains("state.grid")


func test_an_act_zoom_is_journaled_and_replays() -> void:
	await _open(true)
	await _draft()
	var overworld: Control = _flow.overworld
	var guard := 0
	while not overworld.campaign.is_payload_due() and not overworld.campaign.is_lost() and guard < 600:
		guard += 1
		if not overworld.campaign.pending_defense().is_empty():
			overworld._on_defend()
			await _frames(3)
			await _close_modal()
		else:
			overworld._on_wait()
	assert_bool(overworld.campaign.is_payload_due()).is_true()
	overworld.zoom_out()
	await _frames(1)
	assert_int(overworld.campaign.state.act).is_equal(1)
	overworld._on_wait()
	var lines := _journal()
	var zoom := lines.filter(func(l: Dictionary) -> bool: return l.kind == "action" and l.action == "act_zoom")
	assert_int(zoom.size()).is_equal(1)
	assert_bool(lines.any(func(l: Dictionary) -> bool: return l.kind == "snapshot" and l.reason == "act")).is_true()
	assert_int(int(RunFolder.read_summary(_flow.run_dir).act)).is_equal(2)

	var replay := await _replay(lines)
	assert_array(replay.mismatches).is_empty()
	var text := "\n".join(RunTimeline.lines(lines))
	assert_str(text).contains("ACT 1 done")
	assert_str(text).contains("── ACT 2")


func test_continue_resumes_the_same_folder_and_journal() -> void:
	await _open(true)
	await _draft()
	_flow.overworld._on_wait()
	assert_int(_flow.save_run()).is_equal(OK)
	var dir := _flow.run_dir
	var state: Dictionary = _flow.overworld.campaign.state.to_dict()
	_flow.queue_free()
	await _frames(1)
	assert_str(RunFolder.latest_continuable(RUNS_ROOT)).is_equal(dir)

	await _open(true, dir)
	assert_str(_flow.run_dir).is_equal(dir)
	assert_int(_flow.stage).is_equal(RunFlow.Stage.MAP)
	assert_dict(_flow.overworld.campaign.state.to_dict()).is_equal(state)
	var kinds := _kinds(_journal())
	assert_int(kinds.count("run_start")).is_equal(1)
	var sessions := _journal().filter(func(l: Dictionary) -> bool: return l.kind == "session").map(
		func(l: Dictionary) -> String: return str(l.event))
	assert_array(sessions).is_equal(["start", "end", "resume"])
	_flow.overworld._on_wait()
	assert_array((await _replay(_journal())).mismatches).is_empty()


func test_f8_pauses_and_writes_a_report_with_the_save_and_journal() -> void:
	await _open(true)
	await _draft()
	_flow.open_feedback()
	assert_object(_flow.feedback_form).is_not_null()
	assert_bool(get_tree().paused).is_true()
	assert_str(_flow.feedback_form.category()).is_equal("bug")
	assert_int(_flow.feedback_form.rating()).is_equal(3)
	_flow.feedback_form.note_edit.text = "The odds felt wrong."
	_flow.feedback_form.mood_buttons[3].button_pressed = true
	_flow.feedback_form.save_button.pressed.emit()
	assert_bool(get_tree().paused).is_false()
	assert_object(_flow.feedback_form).is_null()
	var report := _flow.last_report_dir
	assert_str(report.get_base_dir()).is_equal(RunFolder.reports_path(_flow.run_dir))
	var note: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(report.path_join("note.json")))
	assert_str(str(note.note)).is_equal("The odds felt wrong.")
	assert_str(str(note.category)).is_equal("bug")
	assert_int(int(note.rating)).is_equal(4)
	assert_str(str(note.stage)).is_equal("map")
	assert_int(int(note.act)).is_equal(1)
	assert_int(int(note.day)).is_equal(1)
	assert_str(str(note.screen)).starts_with("map")
	assert_bool(note.has("variants")).is_true()
	assert_bool(FileAccess.file_exists(report.path_join("run.res"))).is_true()
	assert_bool(FileAccess.file_exists(report.path_join("journal.jsonl"))).is_true()
	assert_str(str(_journal()[-1].kind)).is_equal("feedback")


func test_the_form_and_the_map_open_the_run_folder() -> void:
	await _open(true)
	assert_bool(_flow.folder_button.visible).is_false()
	await _draft()
	assert_bool(_flow.folder_button.visible).is_true()
	_flow.folder_button.pressed.emit()
	_flow.open_feedback()
	_flow.feedback_form.folder_button.pressed.emit()
	_flow.feedback_form.cancel_button.pressed.emit()
	assert_bool(get_tree().paused).is_false()
	var path := ProjectSettings.globalize_path(_flow.run_dir)
	assert_array(_opened).is_equal([path, path])


func test_a_lost_run_is_finished_in_its_summary() -> void:
	await _open(true)
	await _draft()
	var c: Campaign = _flow.overworld.campaign
	# Lose every region: give the recorder the end it would see.
	c.state.owned = PackedStringArray()
	c.changed.emit()
	var summary := RunFolder.read_summary(_flow.run_dir)
	assert_bool(bool(summary.finished)).is_true()
	assert_bool(bool(summary.won)).is_false()
	var end := _journal().filter(func(l: Dictionary) -> bool: return l.kind == "run_end")
	assert_int(end.size()).is_equal(1)
	assert_bool(bool(end[0].won)).is_false()
	summary["dir"] = _flow.run_dir
	summary["has_save"] = true
	assert_bool(RunFolder.can_continue(summary)).is_false()
