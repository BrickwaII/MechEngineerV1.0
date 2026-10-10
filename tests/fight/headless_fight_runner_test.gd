extends GdUnitTestSuite
## The seeded-replay tests here are the most important in the fight suite:
## the same seed and policies must give the same fight, log line for line.

const H := preload("res://tests/fight/fight_test_helpers.gd")


func _request(level: int) -> FightRequest:
	return H.request(H.without_skills(StubSquadProvider.new().get_squad()), level)


func _random_run(level: int, seed_value: int) -> Fight:
	return HeadlessFightRunner.run(_request(level), seed_value, RandomFightPolicy.new(), RandomFightPolicy.new())


func test_same_seed_gives_the_same_log_twice() -> void:
	for level in range(FightRequest.MIN_DEFENSE_LEVEL, FightRequest.MAX_DEFENSE_LEVEL + 1):
		for seed_value in [0, 1, 7, 12345, -99]:
			var first := _random_run(level, seed_value)
			var second := _random_run(level, seed_value)
			assert_str(second.log_text()).is_equal(first.log_text())
			assert_array(second.action_tags).is_equal(first.action_tags)
			var a := first.result()
			var b := second.result()
			assert_int(b.outcome).is_equal(a.outcome)
			assert_float(b.grid_cost).is_equal(a.grid_cost)
			assert_dict(b.rewards).is_equal(a.rewards)


func test_replay_holds_with_waits_in_the_fight() -> void:
	# Seeds whose random play includes at least one wait, so the wait path replays too.
	var with_waits := 0
	for seed_value in 30:
		var first := _random_run(3, seed_value)
		if not first.action_tags.any(func(t: String) -> bool: return t.ends_with(":wait")):
			continue
		with_waits += 1
		assert_str(_random_run(3, seed_value).log_text()).is_equal(first.log_text())
	assert_int(with_waits).is_greater(0)


func test_different_seeds_give_different_fights() -> void:
	var logs := {}
	for seed_value in 10:
		logs[_random_run(2, seed_value).log_text()] = true
	assert_int(logs.size()).is_greater(1)


func test_log_tells_the_whole_fight() -> void:
	var fight := _random_run(1, 5)
	var lines := fight.log_lines
	assert_str(lines[0]).contains("fight start")
	assert_str(lines[lines.size() - 1]).contains("victory" if fight.result().is_victory() else "defeat")
	assert_int(lines.size()).is_greater(fight.action_count)


func test_every_fight_runs_to_its_end() -> void:
	for level in range(FightRequest.MIN_DEFENSE_LEVEL, FightRequest.MAX_DEFENSE_LEVEL + 1):
		var fight := _random_run(level, 11)
		assert_bool(fight.is_over()).is_true()
		assert_int(fight.action_count).is_less_equal(fight.tuning.max_actions)


func test_scripted_policy_is_followed() -> void:
	var policy := ScriptedFightPolicy.new([
		FightAction.wait_for("overload"),
		func(fight: Fight, actor: Combatant) -> FightAction: return FightAction.use("overload", fight.opponents_of(actor)[0].id),
	])
	var fight := HeadlessFightRunner.run(_request(0), 1, policy)
	var squad_tags := fight.action_tags.filter(func(t: String) -> bool: return t.begins_with("stub_"))
	assert_str(squad_tags[0]).ends_with(":wait")
	assert_str(squad_tags[1]).ends_with(":overload")


func test_a_broken_policy_cannot_stall_the_fight() -> void:
	var broken := ScriptedFightPolicy.new([null, FightAction.use("no_such_skill", "nobody")])
	var fight := HeadlessFightRunner.run(_request(0), 1, broken)
	assert_bool(fight.is_over()).is_true()
	assert_str(fight.log_text()).contains("policy refused")


func test_simple_policy_uses_no_randomness() -> void:
	var a := HeadlessFightRunner.run(_request(2), 3, SimpleFightPolicy.new())
	var b := HeadlessFightRunner.run(_request(2), 3, SimpleFightPolicy.new())
	assert_str(b.log_text()).is_equal(a.log_text())
