extends GdUnitTestSuite
## tools/battle_mode_sim.gd: whole runs from the command line, with CSV.

const SIM := preload("res://tools/battle_mode_sim.gd")
const DIR := "user://test_battle_mode_sim"


func after_test() -> void:
	for f in ["fights.csv", "runs.csv"]:
		DirAccess.remove_absolute(DIR.path_join(f))


func test_plays_runs_and_appends_csv() -> void:
	var code := SIM.main(PackedStringArray(["--fights", "2", "--seed", "3", "--runs", "2", "--csv", DIR]))
	assert_int(code).is_equal(0)
	var runs := FileAccess.get_file_as_string(DIR.path_join("runs.csv")).strip_edges().split("\n")
	assert_int(runs.size()).is_equal(3)
	assert_str(runs[1]).contains("gauntlet,3,")
	assert_str(runs[2]).contains("gauntlet,4,")
	var fights := FileAccess.get_file_as_string(DIR.path_join("fights.csv")).strip_edges().split("\n")
	assert_int(fights.size()).is_greater_equal(3)


func test_matches_the_run_api() -> void:
	# The CLI's numbers are BattleModeRun's: same squad, seed and policy.
	SIM.main(PackedStringArray(["--fights", "3", "--seed", "5", "--squad", "skirmish", "--csv", DIR]))
	var run := BattleModeRun.create(BattleModeRun.preset_squad("skirmish"), "gauntlet", 5, FightVariants.defaults())
	run.squad_label = "skirmish"
	run.policy = "simple"
	var s := run.play_to_end(SimpleFightPolicy.new(), IntentFightPolicy.new(), 3)
	var runs := FileAccess.get_file_as_string(DIR.path_join("runs.csv")).strip_edges().split("\n")
	assert_str(runs[1]).is_equal(CsvFile.line(s.csv_row()))


func test_draft_squads_work() -> void:
	assert_int(SIM.main(PackedStringArray(["--fights", "1", "--squad", "draft:7", "--csv", "none"]))).is_equal(0)


func test_the_careful_policy_and_rework_kit_play() -> void:
	assert_int(SIM.main(PackedStringArray(["--fights", "2", "--squad", "rework", "--policy", "careful", "--csv", "none"]))).is_equal(0)


func test_bad_options_fail() -> void:
	assert_int(SIM.main(PackedStringArray(["--length", "forever", "--csv", "none"]))).is_equal(1)
	assert_int(SIM.main(PackedStringArray(["--policy", "psychic", "--csv", "none"]))).is_equal(1)
	assert_int(SIM.main(PackedStringArray(["--squad", "nobody", "--csv", "none"]))).is_equal(1)
	assert_int(SIM.main(PackedStringArray(["--frobnicate", "1"]))).is_equal(1)
