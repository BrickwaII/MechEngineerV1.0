extends GdUnitTestSuite
## Drift is tallied over the fight and applied once, after the last action.
## TODO(decision: d-personality-map): pins the default mapping.

const P := preload("res://tests/fight/post_fight/post_fight_test_helpers.gd")

const AD := Personality.Scale.AGGRESSIVE_DEFENSIVE
const SS := Personality.Scale.SOLITARY_SUPPORTIVE
const RM := Personality.Scale.REACTIVE_METHODICAL


func _pushes(values: Dictionary) -> Dictionary[String, int]:
	var out: Dictionary[String, int] = {}
	for scale: int in Personality.POLES:
		for pole: String in Personality.POLES[scale]:
			out[pole] = values.get(pole, 0)
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

	assert_float(a.personality.aggressive_defensive).is_equal_approx(-0.06, 0.0001)
	assert_float(a.personality.solitary_supportive).is_equal_approx(-0.02, 0.0001)
	assert_float(a.personality.reactive_methodical).is_equal_approx(-0.02, 0.0001)
	# b is generation 1: only aggressive/defensive is active.
	assert_float(b.personality.aggressive_defensive).is_equal_approx(-0.02, 0.0001)
	assert_float(b.personality.solitary_supportive).is_equal(0.0)
	assert_float(b.personality.reactive_methodical).is_equal(0.0)


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


func test_opposite_pushes_cancel() -> void:
	var shifts := PersonalityDrift.shifts(_pushes({"aggressive": 2, "defensive": 2, "solitary": 1, "supportive": 3}), Personality.new(3), P.tuning())
	assert_float(shifts[AD]).is_equal(0.0)
	assert_float(shifts[SS]).is_equal_approx(0.04, 0.0001)


func test_net_drift_is_capped_per_fight() -> void:
	var shifts := PersonalityDrift.shifts(_pushes({"aggressive": 50, "methodical": 50}), Personality.new(3), P.tuning())
	assert_float(shifts[AD]).is_equal_approx(-0.1, 0.0001)
	assert_float(shifts[RM]).is_equal_approx(0.1, 0.0001)


func test_inactive_scales_do_not_move() -> void:
	var pushes := _pushes({"aggressive": 1, "supportive": 1, "methodical": 1})
	var gen2 := PersonalityDrift.shifts(pushes, Personality.new(2), P.tuning())
	assert_float(gen2[AD]).is_not_equal(0.0)
	assert_float(gen2[SS]).is_not_equal(0.0)
	assert_float(gen2[RM]).is_equal(0.0)


func test_values_stay_within_the_scale() -> void:
	var p := Personality.new(1, -0.99)
	PersonalityDrift.apply(p, [-0.1, 0.0, 0.0] as Array[float])
	assert_float(p.aggressive_defensive).is_equal(-1.0)


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
	assert_int(pushes["defensive"]).is_equal(1)
	assert_int(pushes["supportive"]).is_equal(1)


func test_tally_counts_only_the_bot_itself() -> void:
	var mine := ActionTag.new()
	mine.actor_id = "a"
	mine.labels.assign(["wait"])
	var theirs := ActionTag.new()
	theirs.actor_id = "b"
	theirs.labels.assign(["wait"])
	assert_int(PersonalityDrift.tally([mine, theirs] as Array[ActionTag], "a", P.tuning())["methodical"]).is_equal(1)


func test_pole_lookup() -> void:
	assert_int(PersonalityDrift.scale_of_pole("supportive")).is_equal(SS)
	assert_int(PersonalityDrift.direction_of_pole("reactive")).is_equal(-1)
	assert_int(PersonalityDrift.direction_of_pole("methodical")).is_equal(1)
	assert_int(PersonalityDrift.scale_of_pole("grumpy")).is_equal(-1)
