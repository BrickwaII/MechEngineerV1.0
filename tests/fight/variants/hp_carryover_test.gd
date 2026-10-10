extends GdUnitTestSuite
## The hp-carryover options (HpCarryover).


func _variants(option: String) -> FightVariants:
	var v := FightVariants.defaults()
	v.choose(FightVariants.HP_CARRYOVER, option)
	return v


func test_full_heal_is_the_default() -> void:
	var v := FightVariants.defaults()
	assert_int(HpCarryover.hp_after(3, 40, v)).is_equal(40)
	assert_int(HpCarryover.hp_after(0, 40, v)).is_equal(40)


func test_carry_keeps_the_end_hp() -> void:
	var v := _variants(FightVariants.HP_CARRY)
	assert_int(HpCarryover.hp_after(13, 40, v)).is_equal(13)
	assert_int(HpCarryover.hp_after(40, 40, v)).is_equal(40)
	assert_int(HpCarryover.hp_after(0, 40, v)).is_equal(v.param_int(FightVariants.HP_CARRYOVER, "downed_hp"))


func test_partial_heal_adds_a_share_of_max_hp() -> void:
	var v := _variants(FightVariants.HP_PARTIAL_HEAL)
	var percent := v.param_int(FightVariants.HP_CARRYOVER, "heal_percent")
	assert_int(HpCarryover.hp_after(10, 40, v)).is_equal(10 + 40 * percent / 100)
	assert_int(HpCarryover.hp_after(39, 40, v)).is_equal(40)
	assert_int(HpCarryover.hp_after(0, 40, v)).is_equal(
		v.param_int(FightVariants.HP_CARRYOVER, "downed_hp") + 40 * percent / 100)


func test_end_hp_lists_the_squad() -> void:
	var fight := preload("res://tests/fight/fight_test_helpers.gd").duel(UnitStats.new(30, 5, 0, 5, 0, 10), UnitStats.new(30, 5, 0, 5, 0, 10))
	fight.combatant("ally").hp = 12
	assert_dict(HpCarryover.end_hp_by_id(fight)).is_equal({"ally": 12})
	assert_dict(HpCarryover.end_hp_by_id(null)).is_empty()
