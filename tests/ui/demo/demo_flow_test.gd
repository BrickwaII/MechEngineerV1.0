extends GdUnitTestSuite
## Demo runs: every shipped scenario plays without touching the saves folder,
## the demo banner shows, SAVE, LOAD and RUN FOLDER are gone, Home and the Esc
## menu go back to the picker with no confirm, a finished demo offers Replay
## and Back to demos, and F8 writes to the demo reports folder.

const Helpers := preload("res://tests/ui/fight/fight_ui_helpers.gd")
const RunData := preload("res://tests/ui/run/run_data_helpers.gd")
const RUNS_ROOT := "user://test_runs/demo_flow_test"
const REPORTS := "user://test_runs/demo_flow_test_reports"
const VARIANTS := "user://test_runs/demo_flow_test_variants.json"
const JOURNAL_NAMES := ["journal.jsonl", "run.res", "summary.json"]

var _flow: DemoRunFlow
var _exits := 0


func after_test() -> void:
	get_tree().paused = false
	RunData.remove_tree(RUNS_ROOT)
	RunData.remove_tree(REPORTS)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(VARIANTS))
	CampaignVariants.user_path = ""


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _scenario(d: Dictionary) -> DemoScenario:
	var base := {"name": "Test", "description": "A test scenario.", "icon": "time", "act": 1, "kind": "map",
		"squad": {"seed": 13}}
	base.merge(d, true)
	return DemoScenario.from_dict(base, "test")


func _open(scenario: DemoScenario) -> void:
	_exits = 0
	_flow = DemoRunFlow.new()
	_flow.scenario = scenario
	_flow.runs_root = RUNS_ROOT
	_flow.reports_root = REPORTS
	_flow.variants_path = VARIANTS
	_flow.fight_screen_tuning = Helpers.fast_tuning()
	_flow.folder_opener = func(_path: String) -> void: pass
	_flow.exit_requested.connect(func() -> void: _exits += 1)
	var runner := scene_runner(auto_free(_flow))
	await runner.simulate_frames(3)


func _play_out(screen: BattleScreen) -> void:
	var guard := 0
	while is_instance_valid(screen) and not screen.fight.is_over() and guard < 3000:
		if screen.handler.is_player_turn():
			Helpers.play_support_turn_by_mouse(screen)
		else:
			await _frames(1)
		guard += 1


func _assert_nothing_saved() -> void:
	assert_bool(DirAccess.dir_exists_absolute(RUNS_ROOT)).is_false()
	assert_str(_flow.run_dir).is_empty()
	assert_object(_flow.recorder).is_null()


func test_every_shipped_scenario_opens_with_the_banner_and_saves_nothing() -> void:
	for s in DemoScenario.load_all():
		await _open(s)
		assert_object(_flow.end_panel).override_failure_message("%s: %s" % [s.id, _flow.problems]).is_null()
		assert_bool(_flow.banner.visible).is_true()
		assert_str((_flow.banner.get_child(0) as Label).text).contains("DEMO")
		if s.kind == DemoScenario.KIND_FIGHT:
			assert_int(_flow.stage).is_equal(RunFlow.Stage.FIGHT)
			assert_object(_flow.battle_screen).is_not_null()
		elif s.kind != DemoScenario.KIND_RUN_OVER:
			assert_int(_flow.stage).is_equal(RunFlow.Stage.MAP)
			assert_int(_flow.overworld.campaign.state.act).is_equal(s.act_index())
		_flow.save_run()
		_flow._autosave()
		_assert_nothing_saved()
		_flow.go_home()
		assert_int(_exits).override_failure_message(s.id).is_equal(1)
		_flow.queue_free()
		await _frames(1)


func test_the_map_hides_save_load_new_run_and_run_folder() -> void:
	await _open(_scenario({}))
	for b in _flow.overworld.run_buttons:
		assert_bool(b.visible).is_false()
	assert_object(_flow.folder_button).is_null()
	assert_int(_flow.save_run()).is_equal(ERR_UNAVAILABLE)
	assert_bool(_flow.load_run()).is_false()
	assert_object(_flow.overworld.home_button).is_not_null()


func test_home_and_the_esc_menu_go_back_with_no_confirm() -> void:
	await _open(_scenario({"kind": "fight", "fight": {"region": "bellevue", "level": 1}}))
	assert_int(_flow.stage).is_equal(RunFlow.Stage.FIGHT)
	var menu := _flow.open_pause_menu()
	assert_str(menu.home_text).is_equal("Back to demos")
	assert_str(menu.confirm_title).is_empty()
	menu.home_button.pressed.emit()
	assert_int(_exits).is_equal(1)
	assert_bool(get_tree().paused).is_false()
	_flow.battle_screen.home_button.pressed.emit()
	assert_int(_exits).is_equal(2)
	_assert_nothing_saved()


func test_a_demo_fight_ends_on_replay_or_back_to_demos() -> void:
	await _open(_scenario({"kind": "fight", "fight": {"region": "bellevue", "level": 0}}))
	await _play_out(_flow.battle_screen)
	var guard := 0
	while _flow.stage != RunFlow.Stage.POST_FIGHT and guard < 60:
		await _frames(1)
		guard += 1
	_flow.readout.skip()
	assert_str(_flow.continue_button.text).is_equal("DONE")
	_flow.continue_button.pressed.emit()
	await _frames(1)
	assert_object(_flow.end_panel).is_not_null()
	assert_array(["VICTORY", "DEFEAT"]).contains([_flow.end_panel.title_text])
	assert_bool(_flow.overworld.visible).is_false()
	# The map is untouched by a demo fight.
	assert_bool(_flow.overworld.campaign.is_owned("bellevue")).is_false()
	_flow.end_panel.replay_button.pressed.emit()
	await _frames(2)
	assert_object(_flow.end_panel).is_null()
	assert_int(_flow.stage).is_equal(RunFlow.Stage.FIGHT)
	_flow.go_home()
	assert_int(_exits).is_equal(1)
	_assert_nothing_saved()


func test_the_payload_ends_a_map_demo() -> void:
	await _open(_scenario({"day": 101}))
	var overworld: Control = _flow.overworld
	assert_bool(overworld.campaign.is_payload_due()).is_true()
	assert_str(overworld._modal_eyebrow.text).contains("PAYLOAD")
	(overworld._modal_buttons.get_child(0) as Button).pressed.emit()
	assert_object(_flow.end_panel).is_not_null()
	assert_str(_flow.end_panel.title_text).is_equal("PAYLOAD")
	_flow.end_panel.back_button.pressed.emit()
	assert_int(_exits).is_equal(1)


func test_the_run_over_ends_a_map_demo() -> void:
	await _open(_scenario({"losses": 3}))
	var overworld: Control = _flow.overworld
	overworld.campaign.state.ended = Stakes.END_LOSS_LIMIT
	_flow.show_run_over()
	assert_str(_flow.end_panel.title_text).is_equal("RUN OVER · DEFEAT")
	assert_object(_flow.run_over_screen).is_null()


func test_a_forced_defense_opens_on_arrival() -> void:
	await _open(_scenario({"start": "renton_works", "pressure": {"renton": 100}}))
	assert_str(_flow.overworld.campaign.pending_defense()).is_equal("renton")
	assert_str(_flow.overworld._modal_eyebrow.text).contains("FORCED")


func test_a_pre_fight_scenario_opens_the_step() -> void:
	await _open(_scenario({"kind": "pre_fight", "start": "renton_works", "region": "tukwila"}))
	assert_str(_flow.overworld._modal_eyebrow.text).is_equal("ASSAULT")
	assert_str(_flow.overworld._modal_title.text).is_equal("Tukwila")


func test_a_news_card_toasts_on_arrival() -> void:
	await _open(_scenario({"alert_tier": 2, "news": {"kind": "tier"}}))
	await _frames(2)
	var news: Control = _flow.overworld.escalation_hud.news
	assert_bool(news.visible or news.pending() > 0).is_true()


func test_f8_writes_a_demo_report_away_from_the_runs() -> void:
	await _open(_scenario({}))
	_flow.open_feedback()
	assert_bool(get_tree().paused).is_true()
	_flow.feedback_form.note_edit.text = "Demo note."
	_flow.feedback_form.save_button.pressed.emit()
	assert_bool(get_tree().paused).is_false()
	var dir := _flow.last_report_dir
	assert_str(dir.get_base_dir()).is_equal(REPORTS.path_join("test"))
	var note: Dictionary = JsonFile.read(dir.path_join("note.json"))
	assert_bool(bool(note.demo)).is_true()
	assert_str(str(note.scenario)).is_equal("test")
	for name in JOURNAL_NAMES:
		assert_bool(FileAccess.file_exists(dir.path_join(name))).is_false()
	_assert_nothing_saved()


func test_f4_opens_the_switchboard_in_a_demo() -> void:
	await _open(_scenario({}))
	_flow.toggle_switchboard()
	assert_object(_flow.switchboard_screen).is_not_null()
	_flow.toggle_switchboard()
	assert_object(_flow.switchboard_screen).is_null()


func test_a_run_over_scenario_shows_the_screen_then_the_end() -> void:
	await _open(_scenario({"kind": "run_over", "run_over": {"won": false, "end_reason": "loss limit reached", "act": 2, "day": 41}}))
	assert_object(_flow.run_over_screen).is_not_null()
	assert_str(_flow.run_over_screen.title_label.text).is_equal("DEFEAT")
	assert_bool(_flow.run_over_screen.folder_button.visible).is_false()
	_flow.run_over_screen.leave_button.pressed.emit()
	assert_object(_flow.end_panel).is_not_null()
	_assert_nothing_saved()


func test_a_demo_boss_fight_shows_its_boss() -> void:
	for s in DemoScenario.load_all():
		if not s.is_boss():
			continue
		await _open(s)
		var screen := _flow.battle_screen
		assert_str(BattleArt.base_id(screen.boss_id)).override_failure_message(s.id).is_equal(s.boss_unit())
		assert_str(screen.header_label.text).starts_with("BOSS  -  ")
		assert_object(screen.boss_bar).is_not_null()
		assert_bool(MusicDirector.current == null or MusicDirector.current.boss_battle).is_true()
		_flow.queue_free()
		await _frames(1)
