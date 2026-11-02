extends GdUnitTestSuite
## BattleMath reads its damage lines from DamagePipeline's breakdown, so the
## focus card explains Exposed, the payoff and multi-hit totals with the
## fight's own numbers (combat rework S3, ground rule 5). Headless: no screen.

const T := preload("res://tests/fight/intent/intent_test_helpers.gd")


static func _fight() -> Fight:
	var tuning := CombatTuning.load_default()
	tuning.player_skills.assign(["strike", "shred", "heavy_strike"])
	return T.fight(
		[{"id": "a", "stats": T.stats(60, 12, 3, 11, 20)}],
		[{"id": "foe#1", "stats": T.stats(400, 6, 4, 3, 10), "skills": ["strike"]}], tuning)


static func _texts(lines: Array) -> Array[String]:
	var out: Array[String] = []
	for l: Variant in lines:
		out.append((l as UiFormula).text() if l is UiFormula else String(l))
	return out


func test_plain_hit_first_line_ends_with_the_damage() -> void:
	var f := _fight()
	var a := f.combatant("a")
	var foe := f.combatant("foe#1")
	var amount := DamageRules.damage_to(a, foe, a.skill("strike"), f.tuning)
	var lines := _texts(BattleMath.damage_lines(f, "a", foe.id, "strike", amount))
	assert_int(lines.size()).is_equal(1)
	assert_str(lines[0]).ends_with("= %d" % amount)


func test_exposed_and_payoff_get_their_own_lines() -> void:
	var f := _fight()
	var a := f.combatant("a")
	var foe := f.combatant("foe#1")
	f.statuses.apply(foe, "exposed", "a")
	var amount := DamageRules.action_damage_to(a, foe, a.skill("heavy_strike"), f.tuning)
	var lines := _texts(BattleMath.damage_lines(f, "a", foe.id, "heavy_strike", amount))
	var b := DamagePipeline.run(a.stats, foe.stats, a.skill("heavy_strike"), f.tuning, 0, foe)
	assert_array(lines).contains(["%d × Exposed 150%% = %d" % [b.floored, b.after_status]])
	assert_array(lines).contains(["%d × Payoff 150%% = %d" % [b.after_status, b.after_payoff]])
	assert_int(b.final).is_equal(amount)
	# The lines add up to the amount: no "with this turn's bonuses" fudge.
	assert_bool(lines.any(func(l: String) -> bool: return l.begins_with("With this turn"))).is_false()


func test_a_multi_hit_skill_lists_its_hits() -> void:
	var f := _fight()
	var a := f.combatant("a")
	var foe := f.combatant("foe#1")
	var hits := DamagePipeline.hits(a, foe, a.skill("shred"), f.tuning)
	var amount := DamageRules.action_damage_to(a, foe, a.skill("shred"), f.tuning)
	var lines := _texts(BattleMath.damage_lines(f, "a", foe.id, "shred", amount))
	assert_array(lines).contains(["2 hits: %d + %d = %d." % [hits[0].final, hits[1].final, amount]])
