extends GdUnitTestSuite
## BattleModeRun: the loop, growth carried forward, run ends, determinism.

const B := preload("res://tests/fight/battle_mode/battle_mode_test_helpers.gd")
const CSV_DIR := "user://test_battle_mode_run"


func after_test() -> void:
	for f in ["fights.csv", "runs.csv"]:
		DirAccess.remove_absolute(CSV_DIR.path_join(f))


func test_fights_go_on_until_the_gauntlet_is_cleared() -> void:
	var run := B.run("gauntlet")
	var s := run.play_to_end(SimpleFightPolicy.new())
	assert_bool(run.is_over()).is_true()
	assert_bool(run.is_cleared()).is_true()
	assert_int(s.fights()).is_equal(3)
	assert_int(s.won()).is_equal(3)
	assert_str(s.records[2].kind).is_equal("boss")
	assert_str(s.outcome_text()).contains("Cleared")


func test_a_loss_ends_the_run() -> void:
	var t := B.tuning([{"hp_percent": 2000, "attack_percent": 1000}])
	var run := B.run("endless", 1, t)
	var s := run.play_to_end(SimpleFightPolicy.new(), null, 5)
	assert_bool(run.is_over()).is_true()
	assert_bool(run.is_cleared()).is_false()
	assert_int(s.fights()).is_equal(1)
	assert_bool(s.records[0].victory).is_false()
	assert_str(s.outcome_text()).contains("Fell at fight 1")


func test_endless_stops_at_the_cap() -> void:
	var run := B.run("endless")
	var s := run.play_to_end(SimpleFightPolicy.new(), null, 2)
	assert_int(s.fights()).is_equal(2)
	assert_bool(run.is_over()).is_false()
	assert_int(run.fight_number()).is_equal(3)


func test_hp_is_back_to_full_by_default() -> void:
	# TODO(decision: battle-mode-hp): hp-carryover's default heals to full.
	var run := B.run("gauntlet", 1, B.tuning([{"attack_percent": 400, "hp_percent": 500}]))
	var r := run.play_fight(SimpleFightPolicy.new())
	assert_int(r.hp_lost()).is_greater(0)
	for bot in run.squad.bots:
		assert_int(bot.hp).is_equal(bot.get_max_hp())


func test_hp_follows_the_carry_switch() -> void:
	var variants := FightVariants.defaults()
	variants.choose(FightVariants.HP_CARRYOVER, FightVariants.HP_CARRY)
	var run := B.run("gauntlet", 1, B.tuning([{"attack_percent": 400, "hp_percent": 500}]))
	run.variants = variants
	run.play_fight(SimpleFightPolicy.new())
	var hurt := run.squad.bots.filter(func(b: Bot) -> bool: return b.hp < b.get_max_hp())
	assert_int(hurt.size()).is_greater(0)


func test_bots_carry_their_growth_forward() -> void:
	var squad := BattleModeRun.preset_squad("vanguard")
	var run := BattleModeRun.create(squad, "endless", 3, FightVariants.defaults())
	var before := var_to_str(squad.bots.map(func(b: Bot) -> Array: return b.personality.get_ends()))
	var growth_before := _growth(run)
	for i in 4:
		if not run.is_over():
			run.play_fight(SimpleFightPolicy.new())
	var after := var_to_str(squad.bots.map(func(b: Bot) -> Array: return b.personality.get_ends()))
	assert_str(after).is_not_equal(before)
	assert_object(run.last_report).is_not_null()
	assert_int(_growth(run)).is_greater(growth_before)


## Skill levels plus uses banked toward the next, over the fielded bots.
func _growth(run: BattleModeRun) -> int:
	var total := 0
	for bot in run.squad.get_fielded():
		for skill in bot.skills:
			total += run.ledger.get_banked(bot.id, skill.display_name) + skill.level * 1000
	return total


func test_the_same_seed_replays_the_same_run() -> void:
	var a := B.run("endless", 9).play_to_end(SimpleFightPolicy.new(), null, 3)
	var b := B.run("endless", 9).play_to_end(SimpleFightPolicy.new(), null, 3)
	assert_str(a.format_text()).is_equal(b.format_text())
	var c := B.run("endless", 10).play_to_end(SimpleFightPolicy.new(), null, 3)
	assert_str(c.format_text()).is_not_equal(a.format_text())


## The screen plays through FightCommandHandler; its numbers must be the
## headless loop's.
func test_a_fight_played_by_commands_records_what_the_headless_loop_does() -> void:
	var headless := B.run("endless", 4).play_fight(SimpleFightPolicy.new())
	var run := B.run("endless", 4)
	var fight := Fight.new(run.next_request(), run.fight_seed(), run.combat_tuning, run.next_enemy_table())
	run.watch(fight)
	var handler := FightCommandHandler.new(fight, IntentFightPolicy.new())
	handler.action_resolved.connect(func(_id: String, _tag: String) -> void: run.recorder.after_action(fight))
	# The constructor may already have played enemy turns: count them too.
	run.recorder.after_action(fight)
	var policy := SimpleFightPolicy.new()
	var rng := HeadlessFightRunner.policy_rng(fight.fight_seed)
	while not fight.is_over():
		var action := policy.choose(fight, handler.actor(), rng)
		assert_str(handler.apply(FightCommand.select_skill(action.skill_id))).is_empty()
		assert_str(handler.apply(FightCommand.select_target(action.target_id))).is_empty()
	var played := run.finish_fight()
	assert_str(BattleFightRecord.uses_text(played.action_uses)).is_equal(BattleFightRecord.uses_text(headless.action_uses))
	assert_array(played.csv_row("x")).is_equal(headless.csv_row("x"))


func test_csv_rows_are_written_with_one_header() -> void:
	var run := B.run("gauntlet", 2)
	run.play_to_end(SimpleFightPolicy.new())
	assert_int(run.write_csv(CSV_DIR)).is_equal(OK)
	assert_int(run.write_csv(CSV_DIR, "second")).is_equal(OK)
	var fights := FileAccess.get_file_as_string(CSV_DIR.path_join("fights.csv")).strip_edges().split("\n")
	assert_int(fights.size()).is_equal(1 + 3 + 3)
	assert_str(fights[0]).is_equal(",".join(BattleFightRecord.CSV_HEADER))
	assert_str(fights[4]).starts_with("second,1,")
	var runs := FileAccess.get_file_as_string(CSV_DIR.path_join("runs.csv")).strip_edges().split("\n")
	assert_int(runs.size()).is_equal(3)
	assert_str(runs[1]).starts_with(run.run_id() + ",gauntlet,2,")


func test_summary_text_names_actions_and_shares() -> void:
	var run := B.run("gauntlet", 2)
	var s := run.play_to_end(SimpleFightPolicy.new())
	var text := s.format_text(run.action_name)
	assert_str(text).contains("Cleared all 3 fights")
	assert_str(text).contains("Action share: %s 100%%" % run.action_name(s.top_action()))
	assert_str(text).contains("Fights with one action above 50%: 3 of 3")
	assert_int(s.records.size()).is_equal(3)
	assert_str(text).contains("Fight 3 boss: won")
