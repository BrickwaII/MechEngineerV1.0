extends GdUnitTestSuite
## tag-weight per_turn_time and per_fight: a slow bot that acts less often
## grows and levels as much as a fast one. TODO(decision: tag-fairness).

const P := preload("res://tests/fight/post_fight/post_fight_test_helpers.gd")


func _tags(actor: String, ticks: Array) -> Array[ActionTag]:
	var out: Array[ActionTag] = []
	for tick: int in ticks:
		var t := ActionTag.new()
		t.actor_id = actor
		t.kind = FightAction.Kind.SKILL
		t.skill_id = "strike"
		t.tick = tick
		t.labels.assign(["hit_enemy"])
		out.append(t)
	return out


func _tuning(option: String) -> PostFightTuning:
	var t := P.tuning()
	t.tag_weight = option
	t.ticks_per_push = 10.0
	t.pushes_per_fight = 3.0
	return t


## Fast acts every 10 ticks, slow every 20, over the same 60 ticks.
func test_per_turn_time_gives_slow_and_fast_the_same_total() -> void:
	var t := _tuning(FightVariants.TAG_WEIGHT_PER_TURN_TIME)
	var tags := _tags("fast", [10, 20, 30, 40, 50, 60]) + _tags("slow", [20, 40, 60])
	var fast := PersonalityDrift.tally(tags, "fast", t)["aggressive"]
	var slow := PersonalityDrift.tally(tags, "slow", t)["aggressive"]
	assert_float(fast).is_equal_approx(6.0, 1e-6)
	assert_float(slow).is_equal_approx(fast, 1e-6)
	assert_int(SkillProgress.count_uses(tags, "slow", t).get("strike", 0)).is_equal(6)
	assert_int(SkillProgress.count_uses(tags, "fast", t).get("strike", 0)).is_equal(6)


func test_per_fight_shares_a_fixed_budget() -> void:
	var t := _tuning(FightVariants.TAG_WEIGHT_PER_FIGHT)
	var tags := _tags("fast", [10, 20, 30, 40, 50, 60]) + _tags("slow", [20, 40, 60])
	assert_float(PersonalityDrift.tally(tags, "fast", t)["aggressive"]).is_equal_approx(3.0, 1e-6)
	assert_float(PersonalityDrift.tally(tags, "slow", t)["aggressive"]).is_equal_approx(3.0, 1e-6)
	assert_int(SkillProgress.count_uses(tags, "slow", t).get("strike", 0)).is_equal(3)


## Without a weighted rule, uses count one each, as before.
func test_per_action_counts_each_use_once() -> void:
	var t := _tuning(FightVariants.TAG_WEIGHT_PER_ACTION)
	var tags := _tags("slow", [20, 40, 60])
	assert_int(SkillProgress.count_uses(tags, "slow", t).get("strike", 0)).is_equal(3)
	assert_int(SkillProgress.count_uses(tags, "slow").get("strike", 0)).is_equal(3)


func test_the_switch_sets_the_rule_and_its_numbers() -> void:
	var v := FightVariants.defaults()
	assert_bool(v.choose(FightVariants.TAG_WEIGHT, FightVariants.TAG_WEIGHT_PER_TURN_TIME)).is_true()
	var t := PostFightTuning.for_variants(v)
	assert_str(t.tag_weight).is_equal(FightVariants.TAG_WEIGHT_PER_TURN_TIME)
	assert_float(t.ticks_per_push).is_greater(0.0)
	assert_array(t.validate()).is_empty()
