extends GdUnitTestSuite
## DamagePipeline: the ordered damage modifiers (combat rework S3). With no
## status, payoff or guard it gives exactly the pre-pipeline formula; Exposed
## and the payoff stack in a fixed order, before elasticity and guard.

const H := preload("res://tests/fight/fight_test_helpers.gd")

var _tuning: CombatTuning


func before_test() -> void:
	_tuning = CombatTuning.load_default()


## The damage formula as it stood before the pipeline, copied verbatim.
@warning_ignore("integer_division")
static func _legacy(attacker: UnitStats, defender: UnitStats, skill: CombatSkill, tuning: CombatTuning, bonus_percent := 0) -> int:
	bonus_percent += SpeedRules.power_bonus_percent(attacker.speed, tuning)
	var raw := (attacker.attack * skill.power_percent * (100 + bonus_percent) / 100
		- defender.defense * tuning.defense_percent * (100 - clampi(skill.pierce_percent, 0, 100)) / 100)
	var base := maxi(tuning.min_damage, raw / 100)
	return ElasticityRules.reduce(base, defender, tuning)


func _unit(id: String, s: UnitStats, skills: Array[String] = []) -> Combatant:
	return Combatant.new(id, id, Combatant.Side.ENEMY, 0, s, s.hp, skills, _tuning)


func test_steps_are_in_the_documented_order() -> void:
	assert_array(DamagePipeline.STEPS).is_equal(["power", "defense", "floor", "status", "payoff", "elasticity", "guard", "brace"])


func test_no_status_no_payoff_gives_the_old_numbers_for_every_case() -> void:
	var skills: Array[CombatSkill] = []
	for id in _tuning.skills:
		if _tuning.skills[id].is_damage():
			skills.append(_tuning.skills[id])
	var pierced := CombatSkill.new("p", "P", 0, 130)
	pierced.pierce_percent = 40
	skills.append(pierced)
	var checked := 0
	for attack in [1, 4, 9, 15, 30]:
		for defense in [0, 3, 8, 20]:
			for speed in [3, 7, 11]:
				for bonus in [0, 25]:
					for skill in skills:
						var a := H.stats(40, attack, 2, speed, 6)
						var d := H.stats(40, 3, defense, 5, 6, 3)
						var expected := _legacy(a, d, skill, _tuning, bonus)
						assert_int(DamagePipeline.run(a, d, skill, _tuning, bonus).final).is_equal(expected)
						assert_int(DamageRules.damage(a, d, skill, _tuning, bonus)).is_equal(expected)
						# A target with no status and no guard changes nothing either.
						var target := _unit("t", d)
						assert_int(DamagePipeline.run(a, d, skill, _tuning, bonus, target).final).is_equal(expected)
						checked += 1
	assert_int(checked).is_greater(500)


func test_exposed_adds_its_percent_after_the_floor() -> void:
	var a := H.stats(40, 20, 2, 7, 6)
	var target := _unit("t", H.stats(40, 3, 6, 5, 6))
	var skill := _tuning.skill("strike")
	var plain := DamagePipeline.run(a, target.stats, skill, _tuning, 0, target)
	target.statuses.append(StatusInstance.new("exposed"))
	var b := DamagePipeline.run(a, target.stats, skill, _tuning, 0, target)
	assert_int(b.floored).is_equal(plain.final)
	assert_int(b.status_percent).is_equal(50)
	assert_array(b.status_ids).is_equal(["exposed"])
	@warning_ignore("integer_division")
	assert_int(b.final).is_equal(plain.final * 150 / 100)


func test_payoff_needs_its_condition_and_stacks_after_the_status() -> void:
	var a := H.stats(40, 20, 2, 7, 6)
	var target := _unit("t", H.stats(40, 3, 6, 5, 6))
	var heavy := _tuning.skill("heavy_strike")
	var plain := DamagePipeline.run(a, target.stats, heavy, _tuning, 0, target)
	assert_int(plain.payoff_percent).is_equal(0)
	target.statuses.append(StatusInstance.new("exposed"))
	var b := DamagePipeline.run(a, target.stats, heavy, _tuning, 0, target)
	assert_int(b.payoff_percent).is_equal(heavy.payoff_bonus_percent)
	@warning_ignore("integer_division")
	assert_int(b.final).is_equal(plain.final * 150 / 100 * (100 + heavy.payoff_bonus_percent) / 100)
	# Strike has no payoff: only the Exposed bonus.
	var strike := DamagePipeline.run(a, target.stats, _tuning.skill("strike"), _tuning, 0, target)
	assert_int(strike.payoff_percent).is_equal(0)


func test_guard_comes_last() -> void:
	var a := H.stats(40, 20, 2, 7, 6)
	var target := _unit("t", H.stats(40, 3, 6, 5, 6))
	target.statuses.append(StatusInstance.new("exposed"))
	target.guard_percent = 50
	var b := DamagePipeline.run(a, target.stats, _tuning.skill("strike"), _tuning, 0, target)
	assert_int(b.guard_percent).is_equal(50)
	assert_int(b.final).is_equal(DamageRules.guarded(b.before_guard, 50, _tuning))
	assert_int(b.before_guard).is_equal(b.after_payoff)
	assert_int(DamageRules.damage_to(_unit("a", a), target, _tuning.skill("strike"), _tuning)).is_equal(b.final)


func test_multi_hit_uses_exposed_and_guard_on_the_first_hit_only() -> void:
	var attacker := _unit("a", H.stats(40, 20, 2, 7, 6))
	var target := _unit("t", H.stats(400, 3, 6, 5, 6))
	var shred := _tuning.skill("shred")
	assert_int(shred.hit_count).is_equal(2)
	var plain := DamageRules.damage(attacker.stats, target.stats, shred, _tuning)
	target.statuses.append(StatusInstance.new("exposed"))
	var hits := DamagePipeline.hits(attacker, target, shred, _tuning)
	assert_int(hits.size()).is_equal(2)
	@warning_ignore("integer_division")
	assert_int(hits[0].final).is_equal(plain * 150 / 100)
	assert_int(hits[1].final).is_equal(plain)
	assert_int(DamageRules.action_damage_to(attacker, target, shred, _tuning)).is_equal(hits[0].final + hits[1].final)
	# Reads only.
	assert_bool(target.has_status("exposed")).is_true()


func test_multi_hit_stops_when_the_target_would_be_down() -> void:
	var attacker := _unit("a", H.stats(40, 20, 2, 7, 6))
	var target := _unit("t", H.stats(400, 3, 6, 5, 6))
	target.hp = 1
	assert_int(DamagePipeline.hits(attacker, target, _tuning.skill("shred"), _tuning).size()).is_equal(1)


func test_one_hit_skills_total_equals_damage_to() -> void:
	var attacker := _unit("a", H.stats(40, 20, 2, 7, 6))
	var target := _unit("t", H.stats(400, 3, 6, 5, 6))
	target.guard_percent = 40
	for id in ["strike", "heavy_strike", "overload", "arc_sweep"]:
		var s := _tuning.skill(id)
		assert_int(DamageRules.action_damage_to(attacker, target, s, _tuning)).is_equal(DamageRules.damage_to(attacker, target, s, _tuning))
