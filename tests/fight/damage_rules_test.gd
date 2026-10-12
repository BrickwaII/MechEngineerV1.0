extends GdUnitTestSuite
const Legacy := preload("res://tests/fight/legacy_switches.gd")

const H := preload("res://tests/fight/fight_test_helpers.gd")

var _tuning: CombatTuning


func before_test() -> void:
	_tuning = CombatTuning.load_default()
	_tuning.defense_percent = 50
	_tuning.min_damage = 1


func _skill(power: int) -> CombatSkill:
	return CombatSkill.new("s", "S", 0, power)


func test_damage_is_attack_times_power_less_half_defense() -> void:
	# (10 x 100 - 4 x 50) / 100 = 8
	assert_int(DamageRules.damage(H.stats(1, 10, 0, 1, 1), H.stats(1, 0, 4, 1, 1), _skill(100), _tuning)).is_equal(8)
	# (10 x 150 - 4 x 50) / 100 = 13
	assert_int(DamageRules.damage(H.stats(1, 10, 0, 1, 1), H.stats(1, 0, 4, 1, 1), _skill(150), _tuning)).is_equal(13)


func test_damage_rounds_down() -> void:
	# (7 x 100 - 3 x 50) / 100 = 5.5 -> 5
	assert_int(DamageRules.damage(H.stats(1, 7, 0, 1, 1), H.stats(1, 0, 3, 1, 1), _skill(100), _tuning)).is_equal(5)


func test_damage_never_drops_below_the_minimum() -> void:
	assert_int(DamageRules.damage(H.stats(1, 1, 0, 1, 1), H.stats(1, 0, 50, 1, 1), _skill(100), _tuning)).is_equal(1)
	_tuning.min_damage = 3
	assert_int(DamageRules.damage(H.stats(1, 1, 0, 1, 1), H.stats(1, 0, 50, 1, 1), _skill(100), _tuning)).is_equal(3)


func test_identical_inputs_always_give_identical_damage() -> void:
	var a := H.stats(1, 9, 0, 1, 1)
	var d := H.stats(1, 0, 5, 1, 1)
	var first := DamageRules.damage(a, d, _skill(150), _tuning)
	for i in 200:
		assert_int(DamageRules.damage(a, d, _skill(150), _tuning)).is_equal(first)


func test_elasticity_has_no_effect_yet() -> void:
	# TODO(decision: d-elasticity): replace once Elasticity's role is decided.
	var a := H.stats(1, 9, 0, 1, 1)
	var plain := DamageRules.damage(a, H.stats(1, 0, 5, 1, 1, 0), _skill(100), _tuning)
	var stretchy := DamageRules.damage(a, H.stats(1, 0, 5, 1, 1, 99), _skill(100), _tuning)
	assert_int(stretchy).is_equal(plain)
	assert_int(DamageRules.apply_elasticity(17, H.stats(1, 0, 0, 1, 1, 50))).is_equal(17)


func test_a_hit_in_a_fight_uses_the_rule() -> void:
	var ally := H.stats(50, 10, 0, 20, 10)
	var foe := H.stats(50, 1, 4, 1, 10)
	var fight := H.duel(ally, foe)
	fight.advance()
	fight.submit(FightAction.use("strike", "foe#1"))
	var expected := DamageRules.damage(ally, foe, fight.tuning.skill("strike"), fight.tuning)
	assert_int(fight.combatant("foe#1").hp).is_equal(50 - expected)


## These tests' numbers were worked out under the old fight switches.
func before() -> void:
	Legacy.pin()


func after() -> void:
	Legacy.unpin()

