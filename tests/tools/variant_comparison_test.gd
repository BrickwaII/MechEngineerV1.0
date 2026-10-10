extends GdUnitTestSuite
## VariantComparison and the compare_variants command line.

const RUNS := 6


func test_compares_every_option_with_the_default_first() -> void:
	var cmp := VariantComparison.run(FightVariants.WAIT_FORM, RUNS, 1)
	assert_array(cmp.problems).is_empty()
	var options := cmp.results.map(func(r: VariantComparison.OptionResult) -> String: return r.option)
	assert_array(options).is_equal([FightVariants.WAIT_BANKED, FightVariants.WAIT_EXTRA_ENERGY, FightVariants.WAIT_BONUS_DAMAGE])
	assert_bool(cmp.results[0].is_default).is_true()
	for r in cmp.results:
		assert_int(r.report.runs).is_equal(RUNS)


func test_every_comparable_decision_runs() -> void:
	for decision in VariantComparison.comparable():
		var cmp := VariantComparison.run(decision, 2, 1)
		assert_array(cmp.problems).override_failure_message(decision).is_empty()
		assert_int(cmp.results.size()).is_greater(1)


func test_draft_rule_lists_every_rule() -> void:
	var cmp := VariantComparison.run("draft-rule", 2, 1)
	assert_int(cmp.results.size()).is_equal(BotTuning.DRAFT_RULES.size())


func test_same_seeds_give_the_same_table() -> void:
	var a := VariantComparison.run(FightVariants.ELASTICITY, RUNS, 5).format_text()
	assert_str(VariantComparison.run(FightVariants.ELASTICITY, RUNS, 5).format_text()).is_equal(a)


func test_hp_carryover_chains_fights() -> void:
	var cmp := VariantComparison.run(FightVariants.HP_CARRYOVER, RUNS, 1, -1, "", "", 3)
	assert_int(cmp.chain_fights).is_equal(3)
	for r in cmp.results:
		assert_int(r.report.runs).is_between(RUNS, RUNS * 3)
	assert_str(cmp.format_text()).contains("full runs")


func test_drift_off_moves_no_personality() -> void:
	var cmp := VariantComparison.run(FightVariants.PERSONALITY_MAP, RUNS, 1)
	var off: VariantComparison.OptionResult = cmp.results.filter(
		func(r: VariantComparison.OptionResult) -> bool: return r.option == FightVariants.PERSONALITY_OFF)[0]
	assert_float(off.drift_per_bot).is_equal(0.0)
	assert_float(cmp.results[0].drift_per_bot).is_greater(0.0)


func test_unknown_decision_is_a_problem() -> void:
	var cmp := VariantComparison.run("energy-grid", 2, 1)
	assert_array(cmp.problems).is_not_empty()
	assert_str(cmp.format_text()).contains("Cannot compare")


func test_command_line() -> void:
	var main: GDScript = load("res://tools/compare_variants.gd")
	assert_int(main.main(PackedStringArray(["--decision", "d-wait", "--runs", "2"]))).is_equal(0)
	assert_int(main.main(PackedStringArray([]))).is_equal(1)
	assert_int(main.main(PackedStringArray(["--decision", "nope", "--runs", "2"]))).is_equal(1)
	assert_int(main.main(PackedStringArray(["--bogus", "1"]))).is_equal(1)
