extends GdUnitTestSuite
## The main scene: the menu, and a run opened from it.

const RunData := preload("res://tests/ui/run/run_data_helpers.gd")
const RUNS_ROOT := "user://test_runs/main_scene_test"
const LEGACY := "user://test_runs/main_scene_test_legacy.res"


func after_test() -> void:
	RunData.remove_tree(RUNS_ROOT)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LEGACY))


func _menu() -> MainMenu:
	var menu: MainMenu = load("res://ui/main/main.tscn").instantiate()
	menu.runs_root = RUNS_ROOT
	menu.legacy_save = LEGACY
	menu.configure_flow = func(flow: RunFlow) -> void:
		flow.run_seed = 13
		flow.auto_fights = true
	var runner := scene_runner(auto_free(menu))
	await runner.simulate_frames(2)
	return menu


func test_main_scene_loads_and_runs() -> void:
	var runner := scene_runner("res://ui/main/main.tscn")
	await runner.simulate_frames(2)
	assert_object(runner.scene()).is_not_null()
	assert_str(runner.scene().name).is_equal("Main")
	assert_object(runner.scene() as MainMenu).is_not_null()


func test_with_no_runs_only_new_run_is_offered() -> void:
	var menu := await _menu()
	assert_bool(menu.continue_button.disabled).is_true()
	assert_bool(menu.load_button.disabled).is_true()
	assert_bool(menu.new_run_button.disabled).is_false()
	assert_bool(menu.legacy_panel.visible).is_false()


func test_new_run_opens_the_draft_in_a_run_folder_of_its_own() -> void:
	var menu := await _menu()
	menu.new_run_button.pressed.emit()
	await get_tree().process_frame
	var flow := menu.get_node("RunFlow") as RunFlow
	assert_object(flow).is_not_null()
	assert_int(flow.stage).is_equal(RunFlow.Stage.DRAFT)
	assert_object(flow.draft_screen).is_not_null()
	assert_str(flow.run_dir.get_base_dir()).is_equal(RUNS_ROOT)
	assert_str(flow.run_dir.get_file()).ends_with("_13")
	assert_bool(menu.menu.visible).is_false()


func _finished_and_open_runs() -> Array[String]:
	var open := RunFolder.create(RUNS_ROOT, 1)
	var s := RunFolder.new_summary(1, open)
	s.merge({"stage": "map", "act": 2, "day": 9, "updated_unix": 100.0}, true)
	RunFolder.write_summary(open, s)
	var squad := BotFactory.new(BotTuning.load_default()).build_squad(8).to_fielded_squad()
	var map := RegionMap.load_file("res://data/regions/lake_washington_12.json")
	var tuning := MapTuning.load_file("res://data/tuning/act1.json")
	var state := Campaign.new_run_state(map, tuning, map.start_options()[0], CampaignVariants.defaults())
	RunSave.make(1, squad, SkillUseLedger.new(), state).save_file(RunFolder.save_path(open))
	var done := RunFolder.create(RUNS_ROOT, 2)
	var d := RunFolder.new_summary(2, done)
	d.merge({"stage": "map", "finished": true, "won": true, "updated_unix": 200.0}, true)
	RunFolder.write_summary(done, d)
	RunSave.make(2, squad, SkillUseLedger.new(), state).save_file(RunFolder.save_path(done))
	return [open, done]


func test_continue_and_the_load_list() -> void:
	var dirs := _finished_and_open_runs()
	var menu := await _menu()
	assert_bool(menu.continue_button.disabled).is_false()
	assert_str(menu.continue_label.text).contains("Act 2 · Day 9")
	menu.load_button.pressed.emit()
	assert_bool(menu.load_list.visible).is_true()
	assert_int(menu.load_buttons.size()).is_equal(2)
	# A finished run stays listed with its result but cannot be loaded.
	assert_bool(menu.load_buttons[dirs[1]].disabled).is_true()
	assert_str(menu.load_buttons[dirs[1]].text).is_equal("WON")
	assert_bool(menu.load_buttons[dirs[0]].disabled).is_false()
	menu.load_buttons[dirs[0]].pressed.emit()
	await get_tree().process_frame
	assert_object(menu.flow).is_not_null()
	assert_str(menu.flow.run_dir).is_equal(dirs[0])
	assert_int(menu.flow.stage).is_equal(RunFlow.Stage.MAP)


func test_continue_opens_the_latest_open_run() -> void:
	var dirs := _finished_and_open_runs()
	var menu := await _menu()
	menu.continue_button.pressed.emit()
	await get_tree().process_frame
	assert_str(menu.flow.run_dir).is_equal(dirs[0])


func test_the_old_save_is_offered_once() -> void:
	var squad := BotFactory.new(BotTuning.load_default()).build_squad(8)
	var map := RegionMap.load_file("res://data/regions/lake_washington_12.json")
	var tuning := MapTuning.load_file("res://data/tuning/act1.json")
	var state := Campaign.new_run_state(map, tuning, map.start_options()[0], CampaignVariants.defaults())
	DirAccess.make_dir_recursive_absolute(RUNS_ROOT)
	RunSave.make(5, squad, SkillUseLedger.new(), state).save_file(LEGACY)
	var menu := await _menu()
	assert_bool(menu.legacy_panel.visible).is_true()
	var dir := menu.import_legacy()
	assert_str(dir).is_not_empty()
	assert_bool(menu.legacy_panel.visible).is_false()
	assert_bool(menu.continue_button.disabled).is_false()
	menu.continue_button.pressed.emit()
	await get_tree().process_frame
	# The old save kept its bench; the run keeps the squad only.
	assert_int(menu.flow.squad.bots.size()).is_equal(menu.flow.squad.squad_size)
