extends GdUnitTestSuite

const H := preload("res://tests/tools/tools_test_helpers.gd")


func _run(policy: String, runs: int, base_seed: int, log_path := "") -> BatchReport:
	return BatchSimulator.run(H.scenario(policy), runs, base_seed, log_path, H.bot_tuning(), H.enemy_table(), H.combat_tuning())


func test_numbers_on_a_fixed_seed() -> void:
	var r := _run("random", 20, 7)
	assert_int(r.runs).is_equal(20)
	assert_int(r.wins).is_equal(19)
	assert_float(r.win_rate).is_equal_approx(0.95, 0.0001)
	assert_float(r.actions.mean).is_equal_approx(9.5, 0.0001)
	assert_float(r.actions.stddev).is_equal_approx(3.4713, 0.001)
	assert_float(r.actions.min_value).is_equal(5.0)
	assert_float(r.actions.max_value).is_equal(16.0)
	assert_float(r.ticks.mean).is_equal_approx(51.3, 0.0001)
	assert_float(r.squad_energy.mean).is_equal_approx(10.2, 0.0001)


func test_numbers_match_fights_played_one_by_one_with_the_runner() -> void:
	var r := _run("random", 12, 100)
	var resolved := H.scenario("random").resolve(H.bot_tuning(), H.enemy_table(), H.combat_tuning())
	var wins := 0
	var actions := 0
	for i in 12:
		var fight := HeadlessFightRunner.run(
			resolved.request, 100 + i, RandomFightPolicy.new(), SimpleFightPolicy.new(), resolved.tuning, resolved.enemy_table)
		wins += 1 if fight.outcome == FightResult.Outcome.VICTORY else 0
		actions += fight.action_count
		assert_int(r.records[i].seed).is_equal(100 + i)
		assert_int(r.records[i].actions).is_equal(fight.action_count)
	assert_int(r.wins).is_equal(wins)
	assert_float(r.actions.mean).is_equal_approx(actions / 12.0, 0.0001)


func test_the_same_seed_gives_the_same_report() -> void:
	assert_that(_run("random", 10, 3).records).is_equal(_run("random", 10, 3).records)


func test_each_fight_appends_one_log_record() -> void:
	var path := create_temp_dir("batch_log").path_join("stats.jsonl")
	_run("simple", 4, 1, path)
	_run("simple", 3, 50, path)
	var records := FightStatsLog.read_all(path)
	assert_int(records.size()).is_equal(7)
	assert_array(records.map(func(rec: Dictionary) -> int: return int(rec.seed))).is_equal([1, 2, 3, 4, 50, 51, 52])


func test_no_log_path_writes_nothing() -> void:
	var dir := create_temp_dir("batch_nolog")
	_run("simple", 2, 1, "")
	assert_array(DirAccess.get_files_at(dir)).is_empty()


func test_an_unplayable_scenario_reports_why_and_runs_nothing() -> void:
	var s := H.scenario()
	s.squad_entries = []
	var r := BatchSimulator.run(s, 5, 1, "", H.bot_tuning(), H.enemy_table(), H.combat_tuning())
	assert_int(r.runs).is_equal(0)
	assert_array(r.problems).contains(["scenario fields no squad"])
	assert_str(r.format_text()).contains("Cannot run")


func test_the_printed_report_names_win_rate_length_and_energy() -> void:
	var text := _run("random", 20, 7).format_text()
	assert_str(text).contains("Win rate: 95.0%")
	assert_str(text).contains("Fight length, actions: 9.5")
	assert_str(text).contains("Energy spent, squad:   10.2")
	assert_str(text).contains("Left (left)")


func test_the_command_line_runs_a_sample_scenario() -> void:
	var path := create_temp_dir("batch_cli").path_join("cli.jsonl")
	var code := preload("res://tools/batch_sim.gd").main(PackedStringArray([
		"--scenario", "res://data/scenarios/level2_drafted_squad.json", "--runs", "5", "--seed", "11", "--log", path]))
	assert_int(code).is_equal(0)
	assert_int(FightStatsLog.read_all(path).size()).is_equal(5)


func test_the_command_line_fails_on_a_missing_scenario_or_bad_option() -> void:
	var main := preload("res://tools/batch_sim.gd")
	assert_int(main.main(PackedStringArray(["--scenario", "res://data/scenarios/nope.json"]))).is_equal(1)
	assert_int(main.main(PackedStringArray(["--frobnicate", "1"]))).is_equal(1)
	assert_int(main.main(PackedStringArray([]))).is_equal(1)
