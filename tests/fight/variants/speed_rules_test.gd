extends GdUnitTestSuite
## speed-range: the compressed option keeps the fastest unit within 1.6
## times the slowest's turns and pays slow units back in damage; wide is the
## old rule. TODO(decision: speed-range).

const H := preload("res://tests/fight/fight_test_helpers.gd")
const V := preload("res://tests/fight/variants/variant_test_helpers.gd")


func test_wide_is_the_old_rule() -> void:
	var t := V.tuning_with(FightVariants.SPEED_RANGE, FightVariants.SPEED_WIDE)
	assert_int(SpeedRules.charge_per_tick(3, t)).is_equal(3)
	assert_int(SpeedRules.charge_per_tick(11, t)).is_equal(11)
	assert_int(t.turn_threshold()).is_equal(t.action_threshold)
	assert_int(SpeedRules.power_bonus_percent(3, t)).is_equal(0)


func test_compressed_keeps_the_spread_within_the_stand_in() -> void:
	var t := V.tuning_with(FightVariants.SPEED_RANGE, FightVariants.SPEED_COMPRESSED)
	var fastest := SpeedRules.charge_per_tick(99, t)
	var slowest := SpeedRules.charge_per_tick(0, t)
	assert_float(float(fastest) / slowest).is_less_equal(1.6)
	assert_int(SpeedRules.charge_per_tick(7, t)).is_between(slowest, fastest)
	assert_int(t.turn_threshold()).is_greater(t.action_threshold)


func test_compressed_slow_units_hit_harder() -> void:
	var t := V.tuning_with(FightVariants.SPEED_RANGE, FightVariants.SPEED_COMPRESSED)
	assert_int(SpeedRules.power_bonus_percent(11, t)).is_equal(0)
	assert_int(SpeedRules.power_bonus_percent(3, t)).is_greater(SpeedRules.power_bonus_percent(7, t))
	assert_int(SpeedRules.power_bonus_percent(7, t)).is_greater(0)
	var slow := H.stats(20, 10, 0, 3, 10)
	var fast := H.stats(20, 10, 0, 11, 10)
	var target := H.stats(20, 1, 2, 5, 10)
	var strike := t.skill("strike")
	assert_int(DamageRules.damage(slow, target, strike, t)).is_greater(DamageRules.damage(fast, target, strike, t))


func test_compressed_turn_order_follows_the_compressed_charge() -> void:
	var t := V.tuning_with(FightVariants.SPEED_RANGE, FightVariants.SPEED_COMPRESSED)
	var fight := H.duel(H.stats(500, 1, 0, 11, 10), H.stats(500, 1, 0, 3, 10), t)
	var turns := {"ally": 0, "foe#1": 0}
	for entry in fight.upcoming(26):
		turns[entry.combatant_id] += 1
	assert_float(float(turns["ally"]) / turns["foe#1"]).is_less_equal(1.7)
	assert_int(turns["ally"]).is_greater(turns["foe#1"])
