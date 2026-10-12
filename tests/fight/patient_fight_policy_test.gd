extends GdUnitTestSuite
## PatientFightPolicy: waits for its strongest attack instead of a weaker one.
const Legacy := preload("res://tests/fight/legacy_switches.gd")

const H := preload("res://tests/fight/fight_test_helpers.gd")
const V := preload("res://tests/fight/variants/variant_test_helpers.gd")


func test_waits_for_the_strongest_attack() -> void:
	var fight := V.slow_foe_fight(CombatTuning.load_default())
	var ally := fight.advance()
	ally.energy_milli = 1000
	var action := PatientFightPolicy.new().choose(fight, ally, null)
	assert_int(action.kind).is_equal(FightAction.Kind.WAIT)
	assert_str(action.skill_id).is_equal("overload")
	assert_int(action.wait_ticks).is_equal(0)


func test_uses_it_once_affordable() -> void:
	var fight := V.slow_foe_fight(CombatTuning.load_default())
	var ally := fight.advance()
	ally.energy_milli = ally.max_energy_milli
	var action := PatientFightPolicy.new().choose(fight, ally, null)
	assert_int(action.kind).is_equal(FightAction.Kind.SKILL)
	assert_str(action.skill_id).is_equal("overload")


func test_acts_after_a_wait_even_if_still_short() -> void:
	var fight := V.slow_foe_fight(V.tuning_with(FightVariants.WAIT_LENGTH, FightVariants.WAIT_LENGTH_EXACT))
	var ally := fight.advance()
	ally.energy_milli = 0
	fight.submit(FightAction.wait_exact("overload", 1))
	fight.advance()
	assert_int(PatientFightPolicy.new().choose(fight, ally, null).kind).is_equal(FightAction.Kind.SKILL)


func test_names_exact_ticks_that_end_where_a_snap_would() -> void:
	var exact := V.slow_foe_fight(V.tuning_with(FightVariants.WAIT_LENGTH, FightVariants.WAIT_LENGTH_EXACT))
	var snap := V.slow_foe_fight(CombatTuning.load_default())
	for f: Fight in [exact, snap]:
		var ally := f.advance()
		ally.energy_milli = 5 * Combatant.MILLI
		var action := PatientFightPolicy.new().choose(f, ally, null)
		assert_str(f.submit(action)).is_empty()
		f.advance()
	assert_int(exact.decision_tags[0].kind).is_equal(FightAction.Kind.WAIT)
	assert_int(exact.timeline.current_tick).is_equal(snap.timeline.current_tick)


## These tests' numbers were worked out under the old fight switches.
func before() -> void:
	Legacy.pin()


func after() -> void:
	Legacy.unpin()

