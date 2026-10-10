extends GdUnitTestSuite
## The d-personality-map options: which drift rules PostFight uses.


func _variants(option: String) -> FightVariants:
	var v := FightVariants.defaults()
	v.choose(FightVariants.PERSONALITY_MAP, option)
	return v


func _labels(t: PostFightTuning) -> Array:
	return t.drift_rules.map(func(r: PostFightTuning.DriftRule) -> String: return "%s>%s" % [r.label, r.pole])


func test_current_keeps_the_drift_rules() -> void:
	var t := PostFightTuning.for_variants(_variants(FightVariants.PERSONALITY_CURRENT))
	assert_array(_labels(t)).is_equal(_labels(PostFightTuning.load_default()))


func test_by_target_maps_only_target_choices() -> void:
	var t := PostFightTuning.for_variants(_variants(FightVariants.PERSONALITY_BY_TARGET))
	assert_array(_labels(t)).is_not_empty()
	for rule in t.drift_rules:
		assert_array([ActionTag.HIT_ENEMY, ActionTag.SELF_TARGET, ActionTag.ALLY_TARGET]).contains([rule.label])
	assert_array(_labels(t)).is_not_equal(_labels(PostFightTuning.load_default()))


func test_off_has_no_rules_and_moves_nothing() -> void:
	var t := PostFightTuning.for_variants(_variants(FightVariants.PERSONALITY_OFF))
	assert_array(t.drift_rules).is_empty()
	var tag := ActionTag.new()
	tag.actor_id = "a"
	tag.labels = [ActionTag.HIT_ENEMY, ActionTag.WAIT]
	var tags: Array[ActionTag] = [tag]
	var pushes := PersonalityDrift.tally(tags, "a", t)
	for pole in pushes:
		assert_int(pushes[pole]).is_equal(0)


func test_rule_sets_validate() -> void:
	assert_array(PostFightTuning.load_default().validate()).is_empty()
	assert_bool(PostFightTuning.load_default().use_rule_set("no_such_set")).is_false()
