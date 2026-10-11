extends GdUnitTestSuite
## Named skill ranks: names, power, bonuses, fx levels, the uses curve, rank
## progression after a fight, the level-up numbers and the save conversion.
## TODO(decision: skill-ranks): pins the rank structure, not the numbers.

const P := preload("res://tests/fight/post_fight/post_fight_test_helpers.gd")


func test_default_data_loads_and_validates() -> void:
	var r := SkillRanks.load_default()
	assert_object(r).is_not_null()
	assert_array(r.validate()).is_empty()
	# base, +1..+5, Mega, Mega +1..+5, Ultra
	assert_int(r.max_rank()).is_equal(13)


func test_the_default_curve_rises_rank_by_rank() -> void:
	var r := SkillRanks.load_default()
	for i in range(1, r.uses_to_next.size()):
		assert_int(r.uses_to_next[i]).is_greater(r.uses_to_next[i - 1])


func test_rank_names_follow_the_tiers() -> void:
	var r := P.ranks()
	assert_str(r.rank_name("Beam", 1)).is_equal("Beam")
	assert_str(r.rank_name("Beam", 2)).is_equal("Beam +1")
	assert_str(r.rank_name("Beam", 6)).is_equal("Beam +5")
	assert_str(r.rank_name("Beam", 7)).is_equal("Mega Beam")
	assert_str(r.rank_name("Beam", 9)).is_equal("Mega Beam +2")
	assert_str(r.rank_name("Beam", 13)).is_equal("Ultra Beam")
	assert_str(r.rank_name("Beam", 99)).is_equal("Ultra Beam")
	assert_str(r.rank_label(1)).is_equal("")
	assert_str(r.rank_label(3)).is_equal("+2")
	assert_str(r.rank_label(8)).is_equal("Mega +1")


func test_tier_shifts_are_the_first_rank_of_each_later_tier() -> void:
	var r := P.ranks()
	var shifts: Array[int] = []
	for rank in range(1, r.max_rank() + 1):
		if r.is_tier_shift(rank):
			shifts.append(rank)
	assert_array(shifts).is_equal([7, 13])


func test_small_steps_add_a_little_and_tier_shifts_jump() -> void:
	var r := P.ranks()
	assert_int(r.power_bonus_percent(1)).is_equal(0)
	assert_int(r.power_bonus_percent(2)).is_equal(6)
	assert_int(r.power_bonus_percent(6)).is_equal(30)
	assert_int(r.power_bonus_percent(7)).is_equal(55)
	assert_int(r.power_bonus_percent(12)).is_equal(85)
	assert_int(r.power_bonus_percent(13)).is_equal(110)
	var small := r.power_bonus_percent(6) - r.power_bonus_percent(5)
	var jump := r.power_bonus_percent(7) - r.power_bonus_percent(6)
	assert_int(jump).is_greater(small * 3)


func test_bonuses_arrive_with_the_tier_and_grow() -> void:
	var r := P.ranks()
	assert_dict(r.bonuses_at("heavy_strike", 6)).is_empty()
	assert_dict(r.bonuses_at("heavy_strike", 7)).is_equal({"pierce_percent": 50})
	assert_dict(r.bonuses_at("heavy_strike", 13)).is_equal({"pierce_percent": 100})
	assert_dict(r.bonuses_at("strike", 13)).is_empty()


func test_fx_levels_spread_each_tier_and_jump_at_a_shift() -> void:
	var r := P.ranks()
	var fx: Array[int] = []
	for rank in range(1, r.max_rank() + 1):
		fx.append(r.fx_level(rank))
	assert_array(fx).is_equal([1, 1, 1, 2, 2, 3, 5, 5, 6, 6, 7, 8, 10])


func test_apply_names_the_rank_and_carries_the_bonus() -> void:
	var base := CombatSkill.new("heavy_strike", "Heavy Strike", 4, 150)
	var c := P.ranks().apply(base, 7, "Overcharge Shot", 80)
	assert_str(c.display_name).is_equal("Mega Overcharge Shot")
	assert_bool(c.names_rank).is_true()
	assert_int(c.level).is_equal(7)
	assert_int(c.fx_level).is_equal(5)
	assert_int(c.power_percent).is_equal(232)
	assert_int(c.pierce_percent).is_equal(50)
	assert_int(c.energy_cost).is_equal(4)


func test_ranks_climb_by_the_rising_curve_and_bank_the_rest() -> void:
	var t := P.rank_tuning()
	var bot := P.bot("a", 10)
	var ledger := SkillUseLedger.new()
	# 3 to +1, 4 to +2: 8 uses reach +2 with 1 banked.
	var changes := SkillProgress.apply(bot, {"heavy_strike": 8} as Dictionary[String, int], ledger, t)
	assert_int(changes[0].level_before).is_equal(1)
	assert_int(changes[0].level_after).is_equal(3)
	assert_int(changes[0].banked_after).is_equal(1)
	assert_int(changes[0].uses_per_level).is_equal(5)
	assert_str(changes[0].name_after).is_equal("Overcharge Shot +2")
	assert_bool(changes[0].is_tier_shift()).is_false()


func test_reaching_mega_is_a_tier_shift() -> void:
	var t := P.rank_tuning()
	var bot := P.bot("a", 10)
	bot.skills[1].level = 6
	var ledger := SkillUseLedger.new()
	ledger.set_banked("a", "Overcharge Shot", 9)
	var changes := SkillProgress.apply(bot, {"heavy_strike": 1} as Dictionary[String, int], ledger, t, P.combat_tuning())
	var c := changes[0]
	assert_int(c.level_after).is_equal(7)
	assert_bool(c.is_tier_shift()).is_true()
	assert_str(c.rank_before).is_equal("+5")
	assert_str(c.rank_after).is_equal("Mega")
	assert_array(c.new_bonuses).contains_exactly(["pierces 50% of armor"])


func test_the_top_rank_stops_and_banks_nothing() -> void:
	var t := P.rank_tuning()
	var bot := P.bot("a", 10)
	bot.skills[1].level = 12
	var changes := SkillProgress.apply(bot, {"heavy_strike": 500} as Dictionary[String, int], SkillUseLedger.new(), t)
	assert_int(changes[0].level_after).is_equal(13)
	assert_int(changes[0].banked_after).is_equal(0)
	assert_bool(changes[0].is_max_level()).is_true()


## The callout's numbers come from the bot's stats and the combat rules,
## exact before the fight rounds each hit down.
func test_level_up_numbers_use_the_bot_stats_and_combat_rules() -> void:
	var combat := P.combat_tuning()
	var t := P.rank_tuning()
	combat.skill_ranks = t.ranks
	var stats := UnitStats.new(40, 10, 0, 5, 0, 10)
	var before := SkillNumbers.at_level(stats, "heavy_strike", 6, combat, 0)
	var after := SkillNumbers.at_level(stats, "heavy_strike", 7, combat, 0)
	# 150 x 1.30 = 195% of 10 = 19; Mega 150 x 1.55 = 232% = 23.
	assert_str(before.kind).is_equal(SkillNumbers.KIND_DAMAGE)
	assert_float(before.value).is_equal_approx(19.5, 1e-6)
	assert_float(after.value).is_equal_approx(23.2, 1e-6)
	# Rounded down, the same as a real hit on a defenseless target.
	var target := UnitStats.new(40, 1, 0, 1, 0, 1)
	assert_int(floori(after.value)).is_equal(DamageRules.damage(stats, target, combat.skill_at("heavy_strike", 7), combat))
	# And against armor, with Mega's pierce.
	var armored := SkillNumbers.at_level(stats, "heavy_strike", 7, combat, 10)
	target.defense = 10
	assert_int(floori(armored.value)).is_equal(DamageRules.damage(stats, target, combat.skill_at("heavy_strike", 7), combat))
	assert_str(SkillNumbers.format(19.5)).is_equal("19.5")
	assert_str(SkillNumbers.format(23.0)).is_equal("23")


func test_heal_and_guard_numbers() -> void:
	var combat := P.combat_tuning()
	combat.skill_ranks = P.ranks()
	combat.skills["patch_up"] = CombatSkill.new("patch_up", "Patch Up", 3, 100, CombatSkill.EFFECT_HEAL)
	combat.skills["brace"] = CombatSkill.new("brace", "Brace", 2, 50, CombatSkill.EFFECT_GUARD, CombatSkill.TARGET_SELF)
	var stats := UnitStats.new(40, 10, 0, 5, 0, 10)
	assert_float(SkillNumbers.at_level(stats, "patch_up", 1, combat, 0).value).is_equal_approx(10.0, 1e-6)
	assert_float(SkillNumbers.at_level(stats, "patch_up", 2, combat, 0).value).is_equal_approx(10.6, 1e-6)
	assert_float(SkillNumbers.at_level(stats, "patch_up", 7, combat, 0).value).is_equal_approx(15.5, 1e-6)
	assert_str(SkillNumbers.at_level(stats, "brace", 7, combat, 0).kind).is_equal(SkillNumbers.KIND_GUARD)
	assert_float(SkillNumbers.at_level(stats, "brace", 7, combat, 0).value).is_equal(77.0)


func test_flat_levels_still_level_every_uses_per_level() -> void:
	var t := P.tuning()
	var bot := P.bot("a", 10)
	var changes := SkillProgress.apply(bot, {"heavy_strike": 7} as Dictionary[String, int], SkillUseLedger.new(), t)
	assert_int(changes[0].level_after).is_equal(3)
	assert_int(changes[0].banked_after).is_equal(1)
	assert_bool(changes[0].ranked).is_false()


## A format-1 flat level converts to the highest rank no stronger than it.
func test_flat_levels_convert_to_ranks_no_stronger() -> void:
	var r := P.ranks()
	# Flat level n is +10% per level above 1.
	assert_int(r.rank_for_flat_level(1, 10)).is_equal(1)
	assert_int(r.rank_for_flat_level(2, 10)).is_equal(2)
	assert_int(r.rank_for_flat_level(4, 10)).is_equal(6)
	assert_int(r.rank_for_flat_level(6, 10)).is_equal(6)
	assert_int(r.rank_for_flat_level(7, 10)).is_equal(7)
	assert_int(r.rank_for_flat_level(10, 10)).is_equal(12)
	for level in range(1, 11):
		var rank := r.rank_for_flat_level(level, 10)
		assert_int(r.power_bonus_percent(rank)).is_less_equal((level - 1) * 10)
