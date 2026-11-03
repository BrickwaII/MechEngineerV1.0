extends GdUnitTestSuite
## PolicyComparison and the batch_sim --policies entry (the simulation
## harness, combat rework S8).

const H := preload("res://tests/tools/tools_test_helpers.gd")
const SANDBOX := "res://data/scenarios/sandbox_3v3.json"


func _settings(clean := "simple", careless := "greedy") -> HarnessSettings:
	return HarnessSettings.from_dict({"policies": ["greedy", "simple", "random"], "runs": 4, "clean_policy": clean,
		"careless_policy": careless, "max_action_share_percent": 50, "clear_gap_percent": 10, "csv_dir": "none"})


func _run(policies: Array[String], runs := 6, base_seed := 3, settings: HarnessSettings = null) -> PolicyComparison:
	return PolicyComparison.run(H.scenario(), policies, runs, base_seed,
		settings if settings != null else _settings(), H.bot_tuning(), H.enemy_table(), H.combat_tuning())


func _lines(path: String) -> PackedStringArray:
	return FileAccess.get_file_as_string(path).split("\n", false)


func test_a_fixed_seed_gives_the_same_comparison() -> void:
	var names: Array[String] = ["greedy", "random", "smart"]
	var a := _run(names)
	var b := _run(names)
	assert_array(a.problems).is_empty()
	assert_that(a.to_dict()).is_equal(b.to_dict())
	assert_that(a.fights).is_equal(b.fights)
	assert_str(a.format_text()).is_equal(b.format_text())
	assert_that(a.fight_table()).is_equal(b.fight_table())


func test_another_seed_changes_the_random_policy() -> void:
	var names: Array[String] = ["random"]
	assert_that(_run(names, 6, 3).fights).is_not_equal(_run(names, 6, 300).fights)


func test_every_policy_plays_the_same_seeds() -> void:
	var names: Array[String] = ["greedy", "simple"]
	var cmp := _run(names, 5, 10)
	assert_int(cmp.fights.size()).is_equal(10)
	for p in names:
		var seeds := cmp.fights.filter(func(r: Dictionary) -> bool: return r.policy == p).map(
			func(r: Dictionary) -> int: return int(r.seed))
		assert_array(seeds).is_equal([10, 11, 12, 13, 14])
	assert_int(cmp.row("greedy").fights).is_equal(5)


func test_each_record_is_the_fights_own_summary() -> void:
	var names: Array[String] = ["greedy"]
	var cmp := _run(names, 3, 20)
	var resolved := H.scenario().resolve(H.bot_tuning(), H.enemy_table(), H.combat_tuning())
	var hp_lost := 0
	for i in 3:
		var sim := SimulatedFight.new(resolved.request, 20 + i, GreedyFightPolicy.new(), resolved.enemy_policy,
			resolved.tuning, resolved.enemy_table).run_to_end()
		var s := sim.fight.summary()
		var rec := cmp.fights[i]
		assert_that(rec).is_equal(PolicyComparison.fight_record("greedy", 20 + i, s))
		assert_int(rec.hp_lost).is_equal(s.squad.hp_lost())
		assert_float(rec.grid_cost).is_equal(s.grid_cost)
		assert_int(rec.decisions).is_equal(s.squad.decisions)
		hp_lost += s.squad.hp_lost()
	assert_int(cmp.row("greedy").hp_lost).is_equal(hp_lost)


func test_shares_add_up_to_the_decisions() -> void:
	var names: Array[String] = ["random"]
	var r := _run(names, 8, 1).row("random")
	var uses := 0
	var share := 0.0
	for id: String in r.action_uses:
		uses += int(r.action_uses[id])
		share += r.share_percent(id)
	assert_int(uses).is_equal(r.decisions)
	assert_float(share).is_equal_approx(100.0, 0.001)


func test_csv_has_one_row_per_fight_and_per_policy_and_is_replaced() -> void:
	var dir := create_temp_dir("harness_csv")
	var names: Array[String] = ["greedy", "random"]
	var cmp := _run(names, 4, 1)
	assert_int(cmp.write_csv(dir)).is_equal(OK)
	assert_int(cmp.write_csv(dir)).is_equal(OK)
	var fights := _lines(dir.path_join("fights.csv"))
	var policies := _lines(dir.path_join("policies.csv"))
	assert_int(fights.size()).is_equal(1 + 8)
	assert_int(policies.size()).is_equal(1 + 2)
	for col in ["policy", "seed", "won", "hp_lost", "grid_cost", "decisions", "combos", "share_strike"]:
		assert_bool(col in fights[0].split(",")).override_failure_message(col).is_true()
	for col in ["win_rate", "hp_lost", "grid_cost", "check_greedy_loses_more", "check_action_share", "check_clean_win_gap"]:
		assert_bool(col in policies[0].split(",")).override_failure_message(col).is_true()
	assert_str(fights[1]).starts_with("test duo,greedy,1,")


func test_an_unknown_policy_or_none_is_a_problem_and_plays_nothing() -> void:
	var bad: Array[String] = ["greedy", "nope"]
	var cmp := _run(bad)
	assert_array(cmp.problems).is_not_empty()
	assert_array(cmp.fights).is_empty()
	assert_str(cmp.format_text()).contains("cannot compare")
	var none: Array[String] = []
	assert_array(_run(none).problems).is_not_empty()


func test_checks_are_skipped_without_their_policies() -> void:
	var names: Array[String] = ["random"]
	var cmp := _run(names)
	for id in [PolicyComparison.CHECK_GREEDY, PolicyComparison.CHECK_SHARE, PolicyComparison.CHECK_CLEAN_WIN]:
		assert_str(cmp.check(id).verdict).is_equal("skipped")


## A comparison with two hand-made policy rows, to test the checks' rules.
func _checked(clean_hp: Array, careless_hp: Array, clean_uses: Dictionary, wins := true) -> PolicyComparison:
	var cmp := PolicyComparison.new()
	cmp.settings = _settings("smart", "greedy")
	for pair: Array in [["smart", clean_hp, 12.0], ["greedy", careless_hp, 13.0]]:
		var row := PolicyComparison.PolicyRow.new()
		row.policy = pair[0]
		for i in (pair[1] as Array).size():
			var rec := {"policy": pair[0], "seed": i, "won": wins, "timed_out": false, "hp_lost": pair[1][i],
				"hp_start": 100, "grid_cost": pair[2], "energy_spent": 0.0, "decisions": 4, "ticks": 10, "combos": 0,
				"setups": 0, "staggers": 0, "downed": 0, "top_share_percent": 0,
				"action_uses": clean_uses if pair[0] == "smart" else {"strike": 4}}
			cmp._add(row, rec)
			cmp.fights.append(rec)
		cmp.rows.append(row)
	cmp._run_checks()
	return cmp


func test_the_greedy_check_needs_a_clear_hp_gap_and_more_capacity() -> void:
	var even := {"strike": 2, "shred": 2}
	assert_str(_checked([20, 20], [30, 30], even).check(PolicyComparison.CHECK_GREEDY).verdict).is_equal("pass")
	assert_str(_checked([20, 20], [21, 21], even).check(PolicyComparison.CHECK_GREEDY).verdict).is_equal("fail")


func test_the_share_check_reads_the_clean_policys_top_action() -> void:
	assert_str(_checked([1], [9], {"strike": 2, "shred": 2}).check(PolicyComparison.CHECK_SHARE).verdict).is_equal("pass")
	assert_str(_checked([1], [9], {"strike": 3, "shred": 1}).check(PolicyComparison.CHECK_SHARE).verdict).is_equal("fail")


func test_the_clean_win_gap_counts_only_seeds_both_win() -> void:
	var even := {"strike": 2, "shred": 2}
	assert_str(_checked([20, 20], [30, 30], even).check(PolicyComparison.CHECK_CLEAN_WIN).verdict).is_equal("pass")
	var lost := _checked([20, 20], [30, 30], even, false).check(PolicyComparison.CHECK_CLEAN_WIN)
	assert_str(lost.verdict).is_equal("skipped")
	assert_str(lost.detail).contains("no seed")


func test_the_shipped_harness_settings_and_sandbox_are_playable() -> void:
	var settings := HarnessSettings.load_default()
	assert_object(settings).is_not_null()
	assert_array(settings.validate()).is_empty()
	var scenario := ScenarioFiles.load_scenario(settings.scenario)
	assert_object(scenario).is_not_null()
	var resolved := scenario.resolve()
	assert_array(resolved.problems).is_empty()
	var fight := resolved.start(1).fight
	for c in fight.combatants:
		if c.side == Combatant.Side.PLAYER:
			assert_array(c.skill_ids).is_equal(["strike", "shred", "heavy_strike", "brace"])
	assert_array(fight.combatants.filter(func(c: Combatant) -> bool: return c.side == Combatant.Side.ENEMY).map(
		func(c: Combatant) -> String: return c.archetype.id if c.archetype != null else "")).is_equal(
		["charger", "plated", "scaler"])


func test_the_sandbox_comparison_runs_every_default_policy() -> void:
	var settings := HarnessSettings.load_default()
	var cmp := PolicyComparison.run(ScenarioFiles.load_scenario(SANDBOX), settings.policies, 3, 1, settings)
	assert_array(cmp.problems).is_empty()
	assert_int(cmp.rows.size()).is_equal(settings.policies.size())
	assert_int(cmp.checks.size()).is_equal(3)
	for c in cmp.checks:
		assert_str(c.verdict).is_not_equal("skipped")
	for rec in cmp.fights:
		assert_bool(rec.timed_out).is_false()


func test_the_command_line_prints_the_table_and_writes_csv() -> void:
	var dir := create_temp_dir("harness_cli")
	var main := preload("res://tools/batch_sim.gd")
	assert_int(main.main(PackedStringArray(["--policies", "greedy,smart,random", "--runs", "2", "--csv", dir]))).is_equal(0)
	assert_int(_lines(dir.path_join("fights.csv")).size()).is_equal(1 + 6)
	assert_int(main.main(PackedStringArray(["--policies", "default", "--runs", "1", "--csv", "none"]))).is_equal(0)
	assert_int(main.main(PackedStringArray(["--policies", "nope", "--runs", "1", "--csv", "none"]))).is_equal(1)
	assert_int(main.main(PackedStringArray(["--policies", "greedy", "--scenario", "res://nope.json"]))).is_equal(1)


func test_settings_validation() -> void:
	var bad := HarnessSettings.from_dict({"policies": ["nope"], "runs": 0, "clean_policy": "smart",
		"careless_policy": "greedy", "max_action_share_percent": 0, "clear_gap_percent": -1})
	assert_array(bad.validate()).has_size(4)
