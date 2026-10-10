extends GdUnitTestSuite
## Every fight option keeps fights deterministic: the same seed gives the same
## log twice, and the default options give exactly today's fight.

const V := preload("res://tests/fight/variants/variant_test_helpers.gd")
const SEEDS := [1, 2, 3, 4, 5]


func _log(tuning: CombatTuning, seed_value: int) -> String:
	var bots := BotFactory.new(BotTuning.load_default()).build_squad(seed_value).get_fielded()
	var squad: Array[SquadMemberSummary] = []
	for bot in bots:
		squad.append(bot.to_summary())
	var request := FightRequest.new(FightRequest.Kind.ATTACK, "t", 2, squad)
	return HeadlessFightRunner.run(request, seed_value, PatientFightPolicy.new(), IntentFightPolicy.new(), tuning).log_text()


func test_every_option_replays_from_its_seed() -> void:
	for decision: String in FightVariants.KNOWN:
		for option: String in FightVariants.KNOWN[decision]:
			var t := V.tuning_with(decision, option)
			for s: int in SEEDS:
				assert_str(_log(t, s)).override_failure_message("%s=%s seed %d" % [decision, option, s]).is_equal(_log(t, s))


func test_default_options_match_a_tuning_without_switches() -> void:
	var explicit := V.tuning_with(FightVariants.WAIT_FORM, FightVariants.WAIT_BANKED)
	for s: int in SEEDS:
		assert_str(_log(explicit, s)).is_equal(_log(CombatTuning.load_default(), s))


func test_options_that_act_in_a_fight_change_some_fight() -> void:
	var options := {
		FightVariants.WAIT_FORM: [FightVariants.WAIT_EXTRA_ENERGY, FightVariants.WAIT_BONUS_DAMAGE],
		FightVariants.ELASTICITY: [FightVariants.ELASTICITY_BIG_HITS, FightVariants.ELASTICITY_KNOCKBACK, FightVariants.ELASTICITY_ENERGY],
	}
	for decision: String in options:
		for option: String in options[decision]:
			var t := V.tuning_with(decision, option)
			var differs := false
			for s in range(1, 21):
				if _log(t, s) != _log(CombatTuning.load_default(), s):
					differs = true
					break
			assert_bool(differs).override_failure_message("%s=%s changed no fight" % [decision, option]).is_true()
