extends GdUnitTestSuite
## PostFight.apply(): the one entry point after a fight.
const Legacy := preload("res://tests/fight/legacy_switches.gd")

const P := preload("res://tests/fight/post_fight/post_fight_test_helpers.gd")


func test_default_data_loads_and_validates() -> void:
	var tuning := PostFightTuning.load_default()
	assert_object(tuning).is_not_null()
	assert_array(tuning.validate()).is_empty()
	assert_int(tuning.drift_rules.size()).is_equal(6)


func test_every_combat_skill_has_an_entry() -> void:
	var tuning := PostFightTuning.load_default()
	for id in CombatTuning.load_default().player_skills:
		assert_bool(tuning.combat_skill_effects.has(id)).override_failure_message("no entry for %s" % id).is_true()


func test_validate_reports_broken_data() -> void:
	var tuning := P.tuning()
	tuning.drift_rules[0].label = "nonsense"
	tuning.drift_rules[1].pole = "grumpy"
	tuning.uses_per_level = 0
	assert_int(tuning.validate().size()).is_equal(3)


func test_report_covers_each_fielded_bot() -> void:
	var a := P.bot("a", 10)
	var b := P.bot("b", 5)
	var bench := P.bot("c", 5)
	var fight := P.fight_for([a, b])
	P.play(fight, P.sample_steps())
	var report := PostFight.apply(fight, [a, b, bench], null, P.tuning())
	assert_str(report.error).is_empty()
	assert_bool(report.is_victory()).is_true()
	assert_int(report.action_count).is_equal(5)
	assert_array(report.bots.map(func(r: BotFightReport) -> String: return r.bot_id)).contains_exactly(["a", "b"])
	assert_float(bench.personality.aggressive_defensive).is_equal(0.0)

	var ra := report.bot("a")
	assert_int(ra.decisions).is_equal(3)
	assert_int(ra.label_counts["hit_enemy"]).is_equal(3)
	assert_float(ra.growth(Personality.ENDS.find("aggressive"))).is_equal_approx(0.06, 0.0001)
	assert_bool(ra.personality_grew()).is_true()
	# 2 heavy strikes + 0 banked = 0 levels at 3 per level; 1 strike also banks.
	assert_array(ra.level_ups()).is_empty()


func test_ledger_carries_uses_into_the_next_fight() -> void:
	var ledger := SkillUseLedger.new()
	var a := P.bot("a", 10)
	var b := P.bot("b", 5)
	for i in 2:
		var fight := P.fight_for([a, b])
		P.play(fight, P.sample_steps())
		var report := PostFight.apply(fight, [a, b], ledger, P.tuning())
		if i == 1:
			# 4 heavy strikes over two fights: one level, one banked.
			var ups := report.bot("a").level_ups()
			assert_int(ups.size()).is_equal(1)
			assert_str(ups[0].skill_name).is_equal("Overcharge Shot")
			assert_int(ups[0].level_after).is_equal(2)


func test_an_unfinished_fight_changes_nothing() -> void:
	var a := P.bot("a", 10)
	var b := P.bot("b", 5)
	var fight := P.fight_for([a, b])
	P.play(fight, P.sample_steps().slice(0, 2))
	var report := PostFight.apply(fight, [a, b], null, P.tuning())
	assert_str(report.error).is_not_empty()
	assert_array(report.bots).is_empty()
	assert_float(a.personality.aggressive_defensive).is_equal(0.0)


func test_works_on_a_fight_from_the_auto_service() -> void:
	var a := P.bot("a", 10)
	var squad: Array[SquadMemberSummary] = [a.to_summary()]
	var fight := HeadlessFightRunner.run(
		FightRequest.new(FightRequest.Kind.ATTACK, "t", 1, squad), 4, SimpleFightPolicy.new())
	var report := PostFight.apply(fight, [a])
	assert_str(report.error).is_empty()
	assert_int(report.bot("a").decisions).is_equal(
		fight.decision_tags.filter(func(t: ActionTag) -> bool: return t.actor_id == "a").size())


## These tests' numbers were worked out under the old fight switches.
func before() -> void:
	Legacy.pin()


func after() -> void:
	Legacy.unpin()

