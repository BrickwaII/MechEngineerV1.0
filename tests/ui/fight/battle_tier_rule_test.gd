extends GdUnitTestSuite
## The tier-rule switch: which tier a bot is drawn in.

const USER_FILE := "user://tier_rule_test.json"


func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(USER_FILE))


func _choose(option: String) -> void:
	var file := FileAccess.open(USER_FILE, FileAccess.WRITE)
	file.store_string(JSON.stringify({"choices": {"tier-rule": option}}))
	file.close()


func test_the_default_is_generation_with_thresholds_from_data() -> void:
	var rule := BattleTierRule.defaults()
	assert_array(rule.errors).is_empty()
	assert_str(rule.rule).is_equal("generation")
	assert_str(rule.tier_for({"generation": 1})).is_equal("beginner")
	assert_str(rule.tier_for({"generation": rule.medium_at})).is_equal("medium")
	assert_str(rule.tier_for({"generation": rule.advanced_at})).is_equal("advanced")


func test_every_option_is_built_and_read() -> void:
	var board := Switchboard.load_board(USER_FILE)
	for option in BattleTierRule.RULES:
		assert_bool(board.is_built("tier-rule", option)).override_failure_message(option).is_true()
		_choose(option)
		var rule := BattleTierRule.load_active(USER_FILE)
		assert_array(rule.errors).is_empty()
		assert_str(rule.rule).is_equal(option)
		assert_int(rule.advanced_at).is_greater_equal(rule.medium_at)


func test_skill_levels_count_the_levels_gained() -> void:
	_choose("skill_levels")
	var rule := BattleTierRule.load_active(USER_FILE)
	assert_int(rule.score({"skill_levels": [1, 1, 1]})).is_equal(0)
	assert_int(rule.score({"skill_levels": [3, 2, 1]})).is_equal(3)
	assert_str(rule.tier_for({"skill_levels": [1, 1]})).is_equal("beginner")
	assert_str(rule.tier_for({"skill_levels": [1 + rule.medium_at]})).is_equal("medium")
	assert_str(rule.tier_for({"skill_levels": [1 + rule.advanced_at]})).is_equal("advanced")


func test_augments_count_fitted_slots() -> void:
	_choose("augments")
	var rule := BattleTierRule.load_active(USER_FILE)
	var slots: Array[AugmentSlot] = [AugmentSlot.new("plating"), AugmentSlot.new(""), AugmentSlot.new("coil")]
	var bot := Bot.new("b", "B", UnitStats.new(30, 5, 3, 5, 1, 10), Personality.new(1), [], slots)
	var info := BattleTierRule.info_for_bot(bot)
	assert_int(info["augments"]).is_equal(2)
	assert_str(rule.tier_for(info)).is_equal(BattleTierRule.tier_name(rule.tier_index({"augments": 2})))
	assert_str(rule.tier_for({"augments": 0})).is_equal("beginner")


func test_a_bots_generation_and_skills_are_read() -> void:
	var skills: Array[Skill] = [Skill.new("Strike", "damage_single", 0, 4), Skill.new("Brace", "guard_self", 2, 2)]
	var bot := Bot.new("b", "B", UnitStats.new(30, 5, 3, 5, 1, 10), Personality.new(3), skills)
	var info := BattleTierRule.info_for_bot(bot)
	assert_int(info["generation"]).is_equal(3)
	assert_array(info["skill_levels"]).is_equal([4, 2])
	assert_str(BattleTierRule.defaults().tier_for(info)).is_equal("advanced")


func test_an_unknown_choice_falls_back_to_the_default() -> void:
	_choose("nonsense")
	var rule := BattleTierRule.load_active(USER_FILE)
	assert_str(rule.rule).is_equal("generation")
	assert_array(rule.errors).is_not_empty()
