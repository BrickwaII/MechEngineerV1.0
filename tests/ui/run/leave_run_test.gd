extends GdUnitTestSuite
## Leaving a run for the main menu: Esc pauses under the Esc menu, Home on
## the map, battle and readout, the autosave first, the confirm mid-battle,
## the journal's exit line, and Continue coming back to the run.

const SCENE := preload("res://ui/run/run_flow.tscn")
const Helpers := preload("res://tests/ui/fight/fight_ui_helpers.gd")
const RunData := preload("res://tests/ui/run/run_data_helpers.gd")
const RUNS_ROOT := "user://test_runs/leave_run_test"
const VARIANTS := "user://test_runs/leave_run_test_variants.json"
const RUN_SEED := 13

var _flow: RunFlow
var _exits := 0


func after_test() -> void:
	get_tree().paused = false
	RunData.remove_tree(RUNS_ROOT)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(VARIANTS))
	CampaignVariants.user_path = ""
	var overlay := get_tree().root.get_node_or_null("SettingsOverlay")
	if overlay != null:
		get_tree().root.remove_child(overlay)
		overlay.free()


func _open(start_dir := "") -> void:
	_exits = 0
	_flow = SCENE.instantiate()
	_flow.run_seed = RUN_SEED
	_flow.variants_path = VARIANTS
	_flow.fight_screen_tuning = Helpers.fast_tuning()
	_flow.runs_root = RUNS_ROOT
	_flow.start_dir = start_dir
	_flow.exit_requested.connect(func() -> void: _exits += 1)
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


func _escape() -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.physical_keycode = KEY_ESCAPE
	key.pressed = true
	get_viewport().push_input(key)
	await _frames(1)


func _saved_state() -> Dictionary:
	return RunSave.load_file(RunFolder.save_path(_flow.run_dir)).run_state().to_dict()


func test_esc_pauses_the_map_under_the_menu_and_esc_resumes() -> void:
	await _open()
	await _draft()
	await _escape()
	assert_object(_flow.pause_menu).is_not_null()
	assert_bool(get_tree().paused).is_true()
	assert_str(_flow.pause_menu.note_text).contains("saves the run")
	await _escape()
	assert_object(_flow.pause_menu).is_null()
	assert_bool(get_tree().paused).is_false()
	# RESUME closes it too.
	_flow.open_pause_menu()
	_flow.pause_menu.resume_button.pressed.emit()
	assert_object(_flow.pause_menu).is_null()
	assert_bool(get_tree().paused).is_false()


func test_the_menu_stays_shut_under_another_overlay() -> void:
	await _open()
	await _draft()
	_flow.open_feedback()
	assert_object(_flow.open_pause_menu()).is_null()
	_flow.close_feedback()
	_flow.toggle_switchboard()
	assert_object(_flow.open_pause_menu()).is_null()
	_flow.toggle_switchboard()
	assert_object(_flow.open_pause_menu()).is_not_null()


func test_main_menu_from_the_map_saves_first_and_journals_the_exit() -> void:
	await _open()
	await _draft()
	var overworld: Control = _flow.overworld
	assert_object(overworld.home_button).is_not_null()
	assert_str(overworld.home_button.action_icon_id).is_equal("action_home")
	# A wait is not autosaved; leaving saves it.
	overworld._on_wait()
	var state: Dictionary = overworld.campaign.state.to_dict()
	assert_dict(_saved_state()).is_not_equal(state)
	_flow.open_pause_menu()
	_flow.pause_menu.home_button.pressed.emit()
	assert_int(_exits).is_equal(1)
	assert_bool(get_tree().paused).is_false()
	assert_dict(_saved_state()).is_equal(state)
	var exit: Dictionary = _journal().filter(func(l: Dictionary) -> bool: return l.get("action") == "exit")[0]
	assert_str(str(exit.screen)).is_equal("map")
	assert_bool(bool(exit.mid_battle)).is_false()
	assert_str(RunFolder.latest_continuable(RUNS_ROOT)).is_equal(_flow.run_dir)


func test_home_on_the_map_leaves_at_once() -> void:
	await _open()
	await _draft()
	_flow.overworld.home_button.pressed.emit()
	assert_int(_exits).is_equal(1)
	assert_object(_flow.pause_menu).is_null()


func test_leaving_mid_battle_asks_then_comes_back_to_the_map_before_the_fight() -> void:
	await _open()
	await _draft()
	var overworld: Control = _flow.overworld
	var target := _adjacent_target()
	var before: Dictionary = overworld.campaign.state.to_dict()
	overworld._on_attack(target)
	await _frames(1)
	assert_int(_flow.stage).is_equal(RunFlow.Stage.FIGHT)
	# The save made just before the fight is the map as it was.
	assert_dict(_saved_state()).is_equal(before)
	var screen := _flow.battle_screen
	assert_object(screen.home_button).is_not_null()
	# Play a turn, then press Home: it asks first.
	var guard := 0
	while not screen.handler.is_player_turn() and guard < 200:
		await _frames(1)
		guard += 1
	Helpers.play_support_turn_by_mouse(screen)
	screen.home_button.pressed.emit()
	assert_object(_flow.pause_menu).is_not_null()
	assert_bool(_flow.pause_menu.is_confirming()).is_true()
	assert_str(_flow.pause_menu.confirm_body).contains("called off")
	assert_bool(get_tree().paused).is_true()
	assert_int(_exits).is_equal(0)
	# STAY goes back to the menu; Esc then resumes the fight.
	_flow.pause_menu.stay_button.pressed.emit()
	await _escape()
	assert_object(_flow.pause_menu).is_null()
	assert_int(_flow.stage).is_equal(RunFlow.Stage.FIGHT)
	assert_bool(screen.fight.is_over()).is_false()
	# Leave for real.
	_flow.go_home()
	_flow.pause_menu.leave_button.pressed.emit()
	assert_int(_exits).is_equal(1)
	assert_bool(get_tree().paused).is_false()
	assert_dict(_saved_state()).is_equal(before)
	var lines := _journal()
	var ends := lines.filter(func(l: Dictionary) -> bool: return l.kind == RunJournal.KIND_FIGHT_END)
	assert_str(str(ends[-1].outcome)).is_equal(RunJournal.OUTCOME_ABANDONED)
	var exit: Dictionary = lines.filter(func(l: Dictionary) -> bool: return l.get("action") == "exit")[0]
	assert_str(str(exit.screen)).is_equal("fight")
	assert_bool(bool(exit.mid_battle)).is_true()

	# Continue: back on the map before the fight, nothing spent; the same
	# fight can be fought again, and the journal still replays.
	var dir := _flow.run_dir
	_flow.queue_free()
	await _frames(1)
	await _open(dir)
	assert_int(_flow.stage).is_equal(RunFlow.Stage.MAP)
	var campaign: Campaign = _flow.overworld.campaign
	assert_bool(campaign.is_owned(target)).is_false()
	assert_dict(campaign.state.to_dict()).is_equal(before)
	assert_bool(campaign.can_attack(target)).is_true()
	_flow.overworld._on_wait()
	var replay := RunReplay.new(_journal())
	await replay.run()
	assert_array(replay.mismatches).is_empty()
	var timeline := "\n".join(RunTimeline.lines(_journal()))
	assert_str(timeline).contains("ABANDONED")
	assert_str(timeline).contains("left for the main menu (from the fight, mid-battle)")


func test_home_on_the_readout_leaves_with_the_fight_saved() -> void:
	await _open()
	await _draft()
	var overworld: Control = _flow.overworld
	var target := _adjacent_target()
	overworld._on_attack(target)
	await _frames(1)
	var screen := _flow.battle_screen
	var guard := 0
	while not screen.fight.is_over() and guard < 2000:
		if screen.handler.is_player_turn():
			Helpers.play_support_turn_by_mouse(screen)
		else:
			await _frames(1)
		guard += 1
	await _await_stage(RunFlow.Stage.POST_FIGHT)
	assert_object(_flow.readout_home_button).is_not_null()
	_flow.readout_home_button.pressed.emit()
	assert_int(_exits).is_equal(1)
	assert_dict(_saved_state()).is_equal(overworld.campaign.state.to_dict())
	var exit: Dictionary = _journal().filter(func(l: Dictionary) -> bool: return l.get("action") == "exit")[0]
	assert_str(str(exit.screen)).is_equal("post_fight")


func test_leaving_the_draft_asks_and_keeps_nothing_to_continue() -> void:
	await _open()
	_flow.go_home()
	assert_bool(_flow.pause_menu.is_confirming()).is_true()
	_flow.pause_menu.leave_button.pressed.emit()
	assert_int(_exits).is_equal(1)
	assert_str(RunFolder.latest_continuable(RUNS_ROOT)).is_empty()
