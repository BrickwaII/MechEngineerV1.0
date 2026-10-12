extends GdUnitTestSuite
## The d-elasticity options (ElasticityRules).
const Legacy := preload("res://tests/fight/legacy_switches.gd")

const H := preload("res://tests/fight/fight_test_helpers.gd")
const V := preload("res://tests/fight/variants/variant_test_helpers.gd")


func _skill(power: int) -> CombatSkill:
	return CombatSkill.new("test", "Test", 0, power)


func test_none_leaves_damage_alone() -> void:
	var t := CombatTuning.load_default()
	assert_int(ElasticityRules.reduce(30, H.stats(40, 0, 0, 1, 1, 5), t)).is_equal(30)
	assert_int(ElasticityRules.knockback(H.stats(40, 0, 0, 1, 1, 5), t)).is_equal(0)
	assert_int(ElasticityRules.energy_when_hit_milli(H.stats(40, 0, 0, 1, 1, 5), t)).is_equal(0)


func test_reduce_big_hits_cuts_only_the_part_above_the_threshold() -> void:
	var t := V.tuning_with(FightVariants.ELASTICITY, FightVariants.ELASTICITY_BIG_HITS)
	# Max hp 40, big hit above 20% = 8. Elasticity 3 cuts 30% of the excess.
	var defender := H.stats(40, 0, 0, 1, 1, 3)
	assert_int(ElasticityRules.reduce(8, defender, t)).is_equal(8)
	assert_int(ElasticityRules.reduce(18, defender, t)).is_equal(8 + 10 * 70 / 100)
	# No elasticity, no cut.
	assert_int(ElasticityRules.reduce(18, H.stats(40, 0, 0, 1, 1, 0), t)).is_equal(18)


func test_reduce_big_hits_is_capped() -> void:
	var t := V.tuning_with(FightVariants.ELASTICITY, FightVariants.ELASTICITY_BIG_HITS)
	var cap := t.variants.param_int(FightVariants.ELASTICITY, "max_reduce_percent")
	assert_int(ElasticityRules.reduce(108, H.stats(40, 0, 0, 1, 1, 99), t)).is_equal(8 + 100 * (100 - cap) / 100)


func test_reduce_big_hits_applies_in_damage_rules() -> void:
	var t := V.tuning_with(FightVariants.ELASTICITY, FightVariants.ELASTICITY_BIG_HITS)
	var attacker := H.stats(1, 20, 0, 1, 1)
	var plain := DamageRules.damage(attacker, H.stats(40, 0, 0, 1, 1, 0), _skill(100), t)
	var stretchy := DamageRules.damage(attacker, H.stats(40, 0, 0, 1, 1, 5), _skill(100), t)
	assert_int(plain).is_equal(20)
	assert_int(stretchy).is_less(plain)


func test_knockback_is_resisted_by_elasticity() -> void:
	var t := V.tuning_with(FightVariants.ELASTICITY, FightVariants.ELASTICITY_KNOCKBACK)
	var full := t.variants.param_int(FightVariants.ELASTICITY, "knockback_gauge")
	var per := t.variants.param_int(FightVariants.ELASTICITY, "resist_gauge_per_point")
	assert_int(ElasticityRules.knockback(H.stats(1, 0, 0, 1, 1, 0), t)).is_equal(full)
	assert_int(ElasticityRules.knockback(H.stats(1, 0, 0, 1, 1, 2), t)).is_equal(full - 2 * per)
	assert_int(ElasticityRules.knockback(H.stats(1, 0, 0, 1, 1, 99), t)).is_equal(0)


func test_knockback_pushes_the_target_gauge_back_in_a_fight() -> void:
	var t := V.tuning_with(FightVariants.ELASTICITY, FightVariants.ELASTICITY_KNOCKBACK)
	var fight := H.duel(H.stats(50, 5, 0, 50, 10), H.stats(50, 1, 0, 10, 10, 1), t)
	fight.advance()
	var foe := fight.combatant("foe#1")
	var gauge := foe.gauge
	fight.submit(FightAction.use("strike", foe.id))
	assert_int(foe.gauge).is_equal(maxi(0, gauge - ElasticityRules.knockback(foe.stats, t)))


func test_energy_when_hit_refills_the_target() -> void:
	var t := V.tuning_with(FightVariants.ELASTICITY, FightVariants.ELASTICITY_ENERGY)
	var fight := H.duel(H.stats(50, 5, 0, 50, 10), H.stats(50, 1, 0, 1, 10, 4), t)
	fight.advance()
	var foe := fight.combatant("foe#1")
	foe.energy_milli = 0
	fight.submit(FightAction.use("strike", foe.id))
	assert_int(foe.energy_milli).is_equal(4 * t.variants.param_int(FightVariants.ELASTICITY, "energy_milli_per_point"))


func test_after_hit_does_nothing_without_damage() -> void:
	var t := V.tuning_with(FightVariants.ELASTICITY, FightVariants.ELASTICITY_ENERGY)
	var u := Combatant.new("u", "U", Combatant.Side.ENEMY, 0, H.stats(10, 1, 0, 5, 10, 5), 10, t.player_skills, t)
	u.energy_milli = 0
	ElasticityRules.after_hit(u, 0, t)
	assert_int(u.energy_milli).is_equal(0)


## These tests' numbers were worked out under the old fight switches.
func before() -> void:
	Legacy.pin()


func after() -> void:
	Legacy.unpin()

