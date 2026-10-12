extends GdUnitTestSuite
## The d-wait and d-wait-length options (WaitRules).
const Legacy := preload("res://tests/fight/legacy_switches.gd")

const H := preload("res://tests/fight/fight_test_helpers.gd")
const V := preload("res://tests/fight/variants/variant_test_helpers.gd")


func test_banked_recharges_faster_while_waiting() -> void:
	var t := CombatTuning.load_default()
	assert_int(WaitRules.wait_recharge_milli(1000, t)).is_equal(1000 * (100 + t.wait_recharge_bonus_percent) / 100)
	assert_int(WaitRules.start_bonus_milli(t)).is_equal(0)
	assert_int(WaitRules.damage_bonus_percent(true, t)).is_equal(0)


func test_extra_energy_grants_energy_when_the_wait_starts() -> void:
	var t := V.tuning_with(FightVariants.WAIT_FORM, FightVariants.WAIT_EXTRA_ENERGY)
	var points := t.variants.param_int(FightVariants.WAIT_FORM, "extra_energy_points")
	assert_int(WaitRules.wait_recharge_milli(1000, t)).is_equal(1000)
	var fight := V.slow_foe_fight(t)
	var ally := fight.advance()
	ally.energy_milli = 1000
	assert_str(fight.submit(FightAction.wait_for("overload"))).is_empty()
	assert_int(ally.energy_milli).is_equal(1000 + points * Combatant.MILLI)


func test_extra_energy_is_capped_at_the_pool() -> void:
	var fight := V.slow_foe_fight(V.tuning_with(FightVariants.WAIT_FORM, FightVariants.WAIT_EXTRA_ENERGY))
	var ally := fight.advance()
	ally.energy_milli = ally.max_energy_milli - 1
	fight.submit(FightAction.wait_for("overload"))
	assert_int(ally.energy_milli).is_equal(ally.max_energy_milli)


## Damage the ally's strike deals on the turn after a wait, under `t`.
func _strike_after_wait(t: CombatTuning) -> int:
	var fight := V.slow_foe_fight(t)
	var ally := fight.advance()
	fight.submit(FightAction.wait_for("strike"))
	assert_object(fight.advance()).is_same(ally)
	var foe := fight.combatant("foe#1")
	var before := foe.hp
	fight.submit(FightAction.use("strike", foe.id))
	return before - foe.hp


func test_bonus_damage_raises_the_hit_that_ends_a_wait() -> void:
	var t := V.tuning_with(FightVariants.WAIT_FORM, FightVariants.WAIT_BONUS_DAMAGE)
	assert_int(WaitRules.wait_recharge_milli(1000, t)).is_equal(1000)
	var percent := t.variants.param_int(FightVariants.WAIT_FORM, "bonus_damage_percent")
	assert_int(WaitRules.damage_bonus_percent(true, t)).is_equal(percent)
	assert_int(WaitRules.damage_bonus_percent(false, t)).is_equal(0)
	# Attack 5 x 100% x (100 + 25)% = 6.25 -> 6, against 5 without a wait.
	assert_int(_strike_after_wait(t)).is_equal(5 * (100 + percent) / 100)
	assert_int(_strike_after_wait(CombatTuning.load_default())).is_equal(5)


func test_bonus_damage_needs_a_wait() -> void:
	var fight := V.slow_foe_fight(V.tuning_with(FightVariants.WAIT_FORM, FightVariants.WAIT_BONUS_DAMAGE))
	fight.advance()
	var foe := fight.combatant("foe#1")
	var before := foe.hp
	fight.submit(FightAction.use("strike", foe.id))
	assert_int(before - foe.hp).is_equal(5)


func test_exact_waits_are_refused_under_snap() -> void:
	var fight := V.slow_foe_fight(CombatTuning.load_default())
	fight.advance()
	assert_str(fight.check_action(FightAction.wait_exact("strike", 5))).contains("exact waits are off")


func test_exact_wait_lasts_exactly_its_ticks() -> void:
	var t := V.tuning_with(FightVariants.WAIT_LENGTH, FightVariants.WAIT_LENGTH_EXACT)
	for ticks in [1, 7, 30]:
		var fight := V.slow_foe_fight(t)
		var ally := fight.advance()
		var t0 := fight.timeline.current_tick
		assert_str(fight.submit(FightAction.wait_exact("strike", ticks))).is_empty()
		assert_object(fight.advance()).is_same(ally)
		assert_int(fight.timeline.current_tick - t0).is_equal(ticks)


func test_exact_wait_may_end_before_the_skill_is_affordable() -> void:
	var fight := V.slow_foe_fight(V.tuning_with(FightVariants.WAIT_LENGTH, FightVariants.WAIT_LENGTH_EXACT))
	var ally := fight.advance()
	ally.energy_milli = 0
	fight.submit(FightAction.wait_exact("overload", 1))
	assert_object(fight.advance()).is_same(ally)
	assert_bool(ally.can_afford(fight.tuning.skill("overload"))).is_false()


func test_exact_wait_length_is_bounded() -> void:
	var t := V.tuning_with(FightVariants.WAIT_LENGTH, FightVariants.WAIT_LENGTH_EXACT)
	var fight := V.slow_foe_fight(t)
	fight.advance()
	assert_str(fight.check_action(FightAction.wait_exact("strike", -1))).is_not_empty()
	assert_str(fight.check_action(FightAction.wait_exact("strike", WaitRules.max_wait_ticks(t) + 1))).is_not_empty()
	assert_str(fight.check_action(FightAction.wait_exact("strike", WaitRules.max_wait_ticks(t)))).is_empty()


func test_a_wait_naming_no_ticks_still_snaps_under_exact() -> void:
	var snap := V.slow_foe_fight(CombatTuning.load_default())
	var exact := V.slow_foe_fight(V.tuning_with(FightVariants.WAIT_LENGTH, FightVariants.WAIT_LENGTH_EXACT))
	for f: Fight in [snap, exact]:
		f.advance().energy_milli = 5 * Combatant.MILLI
		f.submit(FightAction.wait_for("overload"))
		f.advance()
	assert_int(exact.timeline.current_tick).is_equal(snap.timeline.current_tick)


func test_handler_sends_exact_waits() -> void:
	var fight := V.slow_foe_fight(V.tuning_with(FightVariants.WAIT_LENGTH, FightVariants.WAIT_LENGTH_EXACT))
	var handler := FightCommandHandler.new(fight)
	var t0 := fight.timeline.current_tick
	assert_str(handler.apply(FightCommand.wait("", 4))).is_empty()
	assert_int(fight.timeline.current_tick - t0).is_equal(4)


## These tests' numbers were worked out under the old fight switches.
func before() -> void:
	Legacy.pin()


func after() -> void:
	Legacy.unpin()

