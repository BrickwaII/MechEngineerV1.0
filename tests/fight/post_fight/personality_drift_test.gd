extends GdUnitTestSuite
## Drift is tallied over the fight and applied once, after the last action.
## TODO(decision: d-personality-map): pins the default mapping.

const P := preload("res://tests/fight/post_fight/post_fight_test_helpers.gd")

const SS := Personality.Scale.SOLITARY_SUPPORTIVE


func _pushes(values: Dictionary) -> Dictionary[String, float]:
	var out: Dictionary[String, float] = {}
	for pole in Personality.ENDS:
		out[pole] = float(values.get(pole, 0.0))
	return out


## The test the plan asks for: a sample fight checked against the mapping.
func test_sample_fight_against_the_mapping() -> void:
	var a := P.bot("a", 10, 3)
	var b := P.bot("b", 5, 1)
	var fight := P.fight_for([a, b])
	assert_str(P.play(fight, P.sample_steps())).is_empty()
	var report := PostFight.apply(fight, [a, b], null, P.tuning())

	# a: three hits, one first-affordable, one solo.
	assert_dict(report.bot("a").pole_pushes).is_equal(_pushes({"aggressive": 3, "reactive": 1, "solitary": 1}))
	# b: one wait, one hit, one solo.
	assert_dict(report.bot("b").pole_pushes).is_equal(_pushes({"methodical": 1, "aggressive": 1, "solitary": 1}))

	assert_float(a.personality.aggressive).is_equal_approx(0.06, 0.0001)
	assert_float(a.personality.solitary).is_equal_approx(0.02, 0.0001)
	assert_float(a.personality.reactive).is_equal_approx(0.02, 0.0001)
	# b is generation 1, and every spectrum still grows: the lock is gone.
	assert_float(b.personality.aggressive).is_equal_approx(0.02, 0.0001)
	assert_float(b.personality.solitary).is_equal_approx(0.02, 0.0001)
	assert_float(b.personality.methodical).is_equal_approx(0.02, 0.0001)
	for pole in ["defensive", "supportive"]:
		assert_float(b.personality.get_end(pole)).is_equal(0.0)


func test_no_personality_changes_mid_fight() -> void:
	var a := P.bot("a", 10)
	var b := P.bot("b", 5)
	var before_a := PersonalityDrift.values_of(a.personality)
	var before_b := PersonalityDrift.values_of(b.personality)
	var fight := P.fight_for([a, b])
	var checks := [0]
	var unchanged := func() -> void:
		assert_array(PersonalityDrift.values_of(a.personality)).is_equal(before_a)
		assert_array(PersonalityDrift.values_of(b.personality)).is_equal(before_b)
		checks[0] += 1
	assert_str(P.play(fight, P.sample_steps(), unchanged)).is_empty()
	assert_int(checks[0]).is_equal(5)
	assert_bool(fight.is_over()).is_true()
	PostFight.apply(fight, [a, b], null, P.tuning())
	assert_array(PersonalityDrift.values_of(a.personality)).is_not_equal(before_a)


func test_drift_applies_only_once_per_fight() -> void:
	var a := P.bot("a", 10)
	var b := P.bot("b", 5)
	var fight := P.fight_for([a, b])
	P.play(fight, P.sample_steps())
	PostFight.apply(fight, [a, b], null, P.tuning())
	var after := PersonalityDrift.values_of(a.personality)
	var again := PostFight.apply(fight, [a, b], null, P.tuning())
	assert_str(again.error).is_not_empty()
	assert_array(PersonalityDrift.values_of(a.personality)).is_equal(after)


## The playtest ask: a zigzag does not cancel out. Both ends grow; the larger
## one wins out.
func test_opposite_pushes_both_grow() -> void:
	var grow := PersonalityDrift.growth(_pushes({"aggressive": 2, "defensive": 2, "solitary": 1, "supportive": 3}), P.tuning())
	assert_float(grow[Personality.ENDS.find("aggressive")]).is_equal_approx(0.04, 0.0001)
	assert_float(grow[Personality.ENDS.find("defensive")]).is_equal_approx(0.04, 0.0001)
	assert_float(grow[Personality.ENDS.find("solitary")]).is_equal_approx(0.02, 0.0001)
	assert_float(grow[Personality.ENDS.find("supportive")]).is_equal_approx(0.06, 0.0001)
	var p := Personality.new(3)
	PersonalityDrift.apply(p, grow)
	assert_str(p.get_tag()).is_equal("supportive")


func test_growth_per_end_is_capped_per_fight() -> void:
	var grow := PersonalityDrift.growth(_pushes({"aggressive": 50, "methodical": 50}), P.tuning())
	assert_float(grow[Personality.ENDS.find("aggressive")]).is_equal_approx(0.1, 0.0001)
	assert_float(grow[Personality.ENDS.find("methodical")]).is_equal_approx(0.1, 0.0001)


func test_every_spectrum_grows_at_generation_one() -> void:
	var p := Personality.new(1)
	PersonalityDrift.apply(p, PersonalityDrift.growth(_pushes({"aggressive": 1, "supportive": 1, "methodical": 1}), P.tuning()))
	assert_float(p.aggressive).is_greater(0.0)
	assert_float(p.supportive).is_greater(0.0)
	assert_float(p.methodical).is_greater(0.0)


## The old -1 cap is gone: ends keep growing.
func test_ends_have_no_cap() -> void:
	var p := Personality.new(1, -1.0)
	for i in 20:
		PersonalityDrift.apply(p, PersonalityDrift.growth(_pushes({"aggressive": 5}), P.tuning()))
	assert_float(p.aggressive).is_equal_approx(3.0, 0.0001)
	assert_float(p.get_lean(Personality.Scale.AGGRESSIVE_DEFENSIVE, 1.0)).is_equal(-1.0)


func test_growth_never_shrinks_an_end() -> void:
	var p := Personality.new(3, 0.5)
	PersonalityDrift.apply(p, [-1.0, -1.0, 0.0, 0.0, 0.0, 0.0] as Array[float])
	assert_float(p.defensive).is_equal_approx(0.5, 1e-6)
	assert_float(p.aggressive).is_equal(0.0)


func _tag(actor: String, kind: int, cost_points: int, labels: Array) -> ActionTag:
	var t := ActionTag.new()
	t.actor_id = actor
	t.kind = kind
	t.skill_id = "x"
	t.energy_cost_milli = cost_points * Combatant.MILLI
	t.labels.assign(labels)
	return t


## tag-weight per_energy: a decision counts energy spent / energy_per_push,
## at least min_weight.
func test_per_energy_weights_tags_by_energy_spent() -> void:
	var t := P.tuning()
	var v := FightVariants.defaults()
	v.choose(FightVariants.TAG_WEIGHT, FightVariants.TAG_WEIGHT_PER_ENERGY)
	t.apply_variants(v)
	t.energy_per_push = 3.0
	t.min_weight = 0.25
	var tags: Array[ActionTag] = [
		_tag("a", FightAction.Kind.SKILL, 6, ["hit_enemy"]),
		_tag("a", FightAction.Kind.SKILL, 0, ["hit_enemy"]),
		_tag("a", FightAction.Kind.WAIT, 6, ["wait"]),
	]
	var pushes := PersonalityDrift.tally(tags, "a", t)
	assert_float(pushes["aggressive"]).is_equal_approx(2.25, 1e-6)
	assert_float(pushes["methodical"]).is_equal_approx(0.25, 1e-6)
	t.tag_weight = FightVariants.TAG_WEIGHT_PER_ACTION
	pushes = PersonalityDrift.tally(tags, "a", t)
	assert_float(pushes["aggressive"]).is_equal(2.0)
	assert_float(pushes["methodical"]).is_equal(1.0)


## The fairness the switch is for: a slow bot that acts half as often but
## spends twice the energy per action grows as much under per_energy.
func test_per_energy_evens_out_a_slow_bot() -> void:
	var t := P.tuning()
	t.tag_weight = FightVariants.TAG_WEIGHT_PER_ENERGY
	t.energy_per_push = 3.0
	t.min_weight = 0.25
	var fast: Array[ActionTag] = []
	for i in 6:
		fast.append(_tag("fast", FightAction.Kind.SKILL, 2, ["hit_enemy"]))
	var slow: Array[ActionTag] = []
	for i in 3:
		slow.append(_tag("slow", FightAction.Kind.SKILL, 4, ["hit_enemy"]))
	assert_float(PersonalityDrift.tally(fast, "fast", t)["aggressive"]).is_equal_approx(
		PersonalityDrift.tally(slow, "slow", t)["aggressive"], 1e-6)
	t.tag_weight = FightVariants.TAG_WEIGHT_PER_ACTION
	assert_float(PersonalityDrift.tally(fast, "fast", t)["aggressive"]).is_equal(6.0)
	assert_float(PersonalityDrift.tally(slow, "slow", t)["aggressive"]).is_equal(3.0)


func test_guard_on_self_pushes_defensive_and_ally_skills_push_supportive() -> void:
	var guard := ActionTag.new()
	guard.actor_id = "a"
	guard.skill_id = "brace"
	guard.labels.assign(["self_target"])
	var other_self := ActionTag.new()
	other_self.actor_id = "a"
	other_self.skill_id = "strike"
	other_self.labels.assign(["self_target"])
	var help := ActionTag.new()
	help.actor_id = "a"
	help.skill_id = "patch_up"
	help.labels.assign(["ally_target"])
	var pushes := PersonalityDrift.tally([guard, other_self, help] as Array[ActionTag], "a", P.tuning())
	assert_float(pushes["defensive"]).is_equal(1.0)
	assert_float(pushes["supportive"]).is_equal(1.0)


func test_tally_counts_only_the_bot_itself() -> void:
	var mine := ActionTag.new()
	mine.actor_id = "a"
	mine.labels.assign(["wait"])
	var theirs := ActionTag.new()
	theirs.actor_id = "b"
	theirs.labels.assign(["wait"])
	assert_float(PersonalityDrift.tally([mine, theirs] as Array[ActionTag], "a", P.tuning())["methodical"]).is_equal(1.0)


func test_pole_lookup() -> void:
	assert_int(PersonalityDrift.scale_of_pole("supportive")).is_equal(SS)
	assert_int(PersonalityDrift.direction_of_pole("reactive")).is_equal(-1)
	assert_int(PersonalityDrift.direction_of_pole("methodical")).is_equal(1)
	assert_int(PersonalityDrift.scale_of_pole("grumpy")).is_equal(-1)
