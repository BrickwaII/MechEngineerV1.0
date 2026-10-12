extends GdUnitTestSuite
## The balance sim (BalanceCurve, tools/balance_sim.gd) against the target
## bands in data/combat/difficulty_targets.json.

const RUNS := 4


func test_plays_every_case_of_the_data_file() -> void:
	var curve := BalanceCurve.run(RUNS, 1)
	assert_array(curve.problems).is_empty()
	assert_int(curve.results.size()).is_equal(curve.cases.size())
	assert_int(curve.cases.size()).is_greater(3)
	for r in curve.results:
		assert_int(r.runs).is_equal(RUNS)
		assert_int(r.wins).is_between(0, RUNS)
	assert_str(curve.format_text()).contains("cases on target")
	assert_str(curve.format_markdown()).contains("| Case |")


func test_the_same_seeds_give_the_same_numbers() -> void:
	var a := BalanceCurve.run(RUNS, 5)
	var b := BalanceCurve.run(RUNS, 5)
	for i in a.results.size():
		assert_int(a.results[i].wins).is_equal(b.results[i].wins)


func test_switches_can_play_the_old_behaviour() -> void:
	var curve := BalanceCurve.run(RUNS, 1, {"difficulty-curve": "flat", "speed-range": "wide"})
	assert_array(curve.problems).is_empty()
	assert_str(curve.format_text()).contains("difficulty-curve=flat")
	assert_array(BalanceCurve.run(RUNS, 1, {"difficulty-curve": "nope"}).problems).is_not_empty()


func test_verdict_compares_with_the_band() -> void:
	var c := BalanceCurve.Case.new()
	c.target_low = 40.0
	c.target_high = 60.0
	var r := BalanceCurve.CaseResult.new()
	r.case = c
	r.runs = 10
	r.wins = 3
	assert_str(r.verdict()).is_equal("low")
	r.wins = 5
	assert_str(r.verdict()).is_equal("ok")
	r.wins = 7
	assert_str(r.verdict()).is_equal("high")


func test_parse_reports_bad_cases() -> void:
	var problems: Array[String] = []
	BalanceCurve.parse_cases({"cases": [{"id": "x", "defense_level": 9, "target": [70, 60]}]}, problems)
	assert_int(problems.size()).is_equal(2)
	problems.clear()
	BalanceCurve.parse_cases({}, problems)
	assert_array(problems).contains(["no cases"])


func test_command_line_rejects_bad_options() -> void:
	var main := preload("res://tools/balance_sim.gd")
	assert_int(main.main(PackedStringArray(["--bogus", "1"]))).is_equal(1)
	assert_int(main.main(PackedStringArray(["--set", "nonsense"]))).is_equal(1)
	assert_int(main.main(PackedStringArray(["--runs", "2", "--old", "1"]))).is_equal(0)
