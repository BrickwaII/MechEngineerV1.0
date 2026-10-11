extends GdUnitTestSuite
## RunFolder: one folder per run, summaries, the load list, the old save.

const RunData := preload("res://tests/ui/run/run_data_helpers.gd")
const ROOT := "user://test_runs/run_folder_test"
const LEGACY := "user://test_runs/run_folder_test_legacy.res"
const WHEN := {"year": 2026, "month": 10, "day": 11, "hour": 9, "minute": 5}


func after_test() -> void:
	RunData.remove_tree(ROOT)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LEGACY))


func _run(seed_value: int, summary: Dictionary, save := false) -> String:
	var dir := RunFolder.create(ROOT, seed_value, WHEN)
	var s := RunFolder.new_summary(seed_value, dir)
	s.merge(summary, true)
	RunFolder.write_summary(dir, s)
	if save:
		var file := FileAccess.open(RunFolder.save_path(dir), FileAccess.WRITE)
		file.store_string("x")
		file.close()
	return dir


func test_folders_are_named_by_date_and_seed_and_never_reused() -> void:
	var a := RunFolder.create(ROOT, 42, WHEN)
	var b := RunFolder.create(ROOT, 42, WHEN)
	assert_str(a).is_equal(ROOT.path_join("2026-10-11_0905_42"))
	assert_str(b).is_equal(a + "_2")
	assert_bool(DirAccess.dir_exists_absolute(RunFolder.reports_path(a))).is_true()


func test_the_list_is_newest_first_and_continue_skips_finished_runs() -> void:
	var old := _run(1, {"updated_unix": 100.0}, true)
	var finished := _run(2, {"updated_unix": 300.0, "finished": true, "won": true}, true)
	var unsaved := _run(3, {"updated_unix": 400.0})
	var runs := RunFolder.list(ROOT)
	assert_array(runs.map(func(s: Dictionary) -> String: return s.dir)).is_equal([unsaved, finished, old])
	assert_bool(runs[0].has_save).is_false()
	assert_str(RunFolder.latest_continuable(ROOT)).is_equal(old)
	assert_int(RunFolder.list(ROOT, 2).size()).is_equal(2)


func test_the_one_line_summary() -> void:
	var s := RunFolder.new_summary(5, "x")
	s.merge({"stage": "map", "act": 2, "day": 14, "regions_held": 9, "regions_total": 22,
		"fights_won": 5, "fights_lost": 2, "play_s": 3840.0}, true)
	assert_str(RunFolder.describe(s)).is_equal("Act 2 · Day 14 · 9/22 regions · 5 won 2 lost · 1h 04m · in progress")
	s.finished = true
	assert_str(RunFolder.describe(s)).ends_with("· lost")
	assert_str(RunFolder.describe(RunFolder.new_summary(5, "x"))).starts_with("Draft ·")


func test_the_old_save_is_offered_once_as_a_run_of_its_own() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT)
	assert_bool(RunFolder.legacy_pending(ROOT, LEGACY)).is_false()
	var squad := BotFactory.new(BotTuning.load_default()).build_squad(8)
	var map := RegionMap.load_file("res://data/regions/lake_washington_12.json")
	var tuning := MapTuning.load_file("res://data/tuning/act1.json")
	var state := Campaign.new_run_state(map, tuning, null, CampaignVariants.defaults())
	state.time_points = 9
	assert_int(RunSave.make(77, squad, SkillUseLedger.new(), state).save_file(LEGACY)).is_equal(OK)
	assert_bool(RunFolder.legacy_pending(ROOT, LEGACY)).is_true()
	var dir := RunFolder.import_legacy(ROOT, LEGACY)
	assert_str(dir.get_file()).ends_with("_77")
	assert_object(RunSave.load_file(RunFolder.save_path(dir))).is_not_null()
	var summary := RunFolder.read_summary(dir)
	assert_bool(bool(summary.imported)).is_true()
	assert_int(int(summary.act)).is_equal(1)
	assert_int(int(summary.day)).is_equal(3)
	assert_int(int(summary.regions_total)).is_equal(12)
	# Offered once: not again, and the old file stays where it was.
	assert_bool(RunFolder.legacy_pending(ROOT, LEGACY)).is_false()
	assert_bool(FileAccess.file_exists(LEGACY)).is_true()
