extends GdUnitTestSuite
## strike-cost: Strike costs energy and recharge slows, so a bot chooses
## between Strike, a bigger skill and waiting; free is the old rule.
## TODO(decision: strike-cost).

const H := preload("res://tests/fight/fight_test_helpers.gd")
const V := preload("res://tests/fight/variants/variant_test_helpers.gd")


func test_free_is_the_old_rule() -> void:
	var t := V.tuning_with(FightVariants.STRIKE_COST, FightVariants.STRIKE_FREE)
	assert_int(t.skill("strike").energy_cost).is_equal(0)
	assert_int(EnergyRules.recharge_milli_per_battery(t)).is_equal(t.recharge_milli_per_battery_per_tick)
	assert_int(EnergyRules.recharge_floor_milli(t)).is_equal(t.recharge_floor_milli_per_tick)


func test_costs_puts_the_cost_on_strike_only() -> void:
	var t := V.tuning_with(FightVariants.STRIKE_COST, FightVariants.STRIKE_COSTS)
	var cost := t.variants.param_int(FightVariants.STRIKE_COST, "energy_cost")
	assert_int(cost).is_greater(0)
	assert_int(t.skill("strike").energy_cost).is_equal(cost)
	assert_int(t.skill("heavy_strike").energy_cost).is_equal(t.skills["heavy_strike"].energy_cost)
	# The data stays as written; the switch applies on the way out.
	assert_int(t.skills["strike"].energy_cost).is_equal(0)
	# A unit's own (ranked) Strike costs the same, so the skill card shows it.
	assert_int(t.skill_at("strike", 4).energy_cost).is_equal(cost)
	var card: SkillCard = auto_free(SkillCard.make(t.skill("strike").display_name, t.skill("strike").energy_cost, ""))
	assert_str(card.cost_label.text).is_equal(str(cost))


func test_costs_uses_its_own_recharge() -> void:
	var t := V.tuning_with(FightVariants.STRIKE_COST, FightVariants.STRIKE_COSTS)
	var per_battery := t.variants.param_int(FightVariants.STRIKE_COST, "recharge_milli_per_battery_per_tick")
	var c := Combatant.new("a", "A", Combatant.Side.PLAYER, 0, H.stats(10, 1, 0, 5, 10), 10, ["strike"] as Array[String], t)
	assert_int(c.recharge_milli).is_equal(maxi(EnergyRules.recharge_floor_milli(t), 10 * per_battery))


func test_a_unit_that_cannot_afford_strike_waits_for_it() -> void:
	var t := V.tuning_with(FightVariants.STRIKE_COST, FightVariants.STRIKE_COSTS)
	var fight := V.slow_foe_fight(t)
	var ally := fight.advance()
	ally.energy_milli = 0
	assert_str(fight.check_action(FightAction.use("strike", "foe#1"))).contains("cannot afford")
	var action := SimpleFightPolicy.new().choose(fight, ally, null)
	assert_int(action.kind).is_equal(FightAction.Kind.WAIT)
	assert_str(fight.submit(action)).is_empty()
	assert_object(fight.advance()).is_same(ally)
	assert_bool(ally.can_afford(t.skill("strike"))).is_true()


func test_auto_fights_still_finish_with_a_costed_strike() -> void:
	var t := V.tuning_with(FightVariants.STRIKE_COST, FightVariants.STRIKE_COSTS)
	var squad: Array[SquadMemberSummary] = [H.member("a", H.stats(30, 6, 2, 6, 6))]
	var fight := HeadlessFightRunner.run(H.request(H.without_skills(squad), 1), 3, SimpleFightPolicy.new(), null, t)
	assert_bool(fight.is_over()).is_true()
	assert_bool(fight.timed_out).is_false()
