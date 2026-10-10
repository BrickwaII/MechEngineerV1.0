extends GdUnitTestSuite

const Snapshot := preload("res://tests/bot_data/resource_snapshot.gd")

var _tuning: BotTuning
var _factory: BotFactory


func before_test() -> void:
	_tuning = BotTuning.load_default()
	_factory = BotFactory.new(_tuning)


func test_the_draft_size_comes_from_data() -> void:
	assert_array(_factory.build_draft(1)).has_size(_tuning.draft_size)
	_tuning.draft_size = 4
	assert_array(_factory.build_draft(1)).has_size(4)


func test_the_same_seed_gives_the_same_draft() -> void:
	assert_that(Snapshot.of(_factory.build_draft(1234))).is_equal(Snapshot.of(_factory.build_draft(1234)))


func test_a_new_factory_gives_the_same_draft_for_the_seed() -> void:
	var other := BotFactory.new(BotTuning.load_default())
	assert_that(Snapshot.of(other.build_draft(77))).is_equal(Snapshot.of(_factory.build_draft(77)))


func test_global_randomness_does_not_change_the_draft() -> void:
	var first: Variant = Snapshot.of(_factory.build_draft(42))
	seed(987654)
	randi()
	assert_that(Snapshot.of(_factory.build_draft(42))).is_equal(first)


func test_different_seeds_give_different_drafts() -> void:
	assert_that(Snapshot.of(_factory.build_draft(1))).is_not_equal(Snapshot.of(_factory.build_draft(2)))


func test_every_drafted_bot_is_valid_for_the_tuning() -> void:
	for seed_value in range(20):
		for bot in _factory.build_draft(seed_value):
			assert_array(_tuning.validation_errors_for(bot)).is_empty()


func test_drafted_bots_have_distinct_ids_and_names() -> void:
	var draft := _factory.build_draft(8)
	var ids := {}
	var names := {}
	for bot in draft:
		ids[bot.id] = true
		names[bot.display_name] = true
	assert_int(ids.size()).is_equal(draft.size())
	assert_int(names.size()).is_equal(draft.size())


func test_stats_vary_within_their_ranges_across_drafts() -> void:
	var seen := {}
	for seed_value in range(10):
		for bot in _factory.build_draft(seed_value):
			seen[bot.stats.attack] = true
	assert_int(seen.size()).is_greater(1)


func test_drafted_bots_start_at_full_hp_with_starting_skills() -> void:
	for bot in _factory.build_draft(3):
		assert_int(bot.hp).is_equal(bot.stats.hp)
		assert_array(bot.skills).has_size(_tuning.starting_skill_count)


func test_drafted_personality_uses_only_the_active_scales() -> void:
	for bot in _factory.build_draft(11):
		assert_int(bot.personality.generation).is_equal(_tuning.starting_generation)
		for scale in Personality.SCALE_COUNT:
			var value := bot.personality.get_raw_value(scale)
			if bot.personality.is_active(scale):
				assert_float(value).is_between(_tuning.personality_start_range.x, _tuning.personality_start_range.y)
			else:
				assert_float(value).is_equal(0.0)


func test_drafted_bots_do_not_share_skill_objects_with_the_catalog() -> void:
	var bot := _factory.build_draft(4)[0]
	bot.skills[0].level = 9
	for skill in _tuning.skills:
		assert_int(skill.level).is_equal(Skill.MIN_LEVEL)


func test_a_built_squad_holds_the_draft_and_fields_squad_size() -> void:
	var squad := _factory.build_squad(5)
	assert_array(squad.validation_errors()).is_empty()
	assert_array(squad.bots).has_size(_tuning.draft_size)
	assert_int(squad.squad_size).is_equal(_tuning.squad_size)
	assert_array(squad.get_fielded()).has_size(_tuning.squad_size)


func test_a_squad_rejects_bad_fielding() -> void:
	var squad := _factory.build_squad(5)
	squad.fielded_ids.append("nobody")
	assert_bool(squad.is_valid()).is_false()
	squad = _factory.build_squad(5)
	squad.fielded_ids = [squad.bots[0].id, squad.bots[0].id]
	assert_bool(squad.is_valid()).is_false()
	squad = _factory.build_squad(5)
	for bot in squad.bots:
		if not bot.id in squad.fielded_ids:
			squad.fielded_ids.append(bot.id)
	assert_bool(squad.is_valid()).is_false()


func test_a_squad_rejects_duplicate_bot_ids() -> void:
	var squad := _factory.build_squad(5)
	squad.bots[1].id = squad.bots[0].id
	assert_bool(squad.is_valid()).is_false()


func _has_damage_skill(bot: Bot, tuning: BotTuning) -> bool:
	return bot.skills.any(func(s: Skill) -> bool: return tuning.is_damage_skill(s))


func test_the_draft_rule_comes_from_data() -> void:
	assert_str(_tuning.draft_rule).is_equal(BotTuning.DRAFT_RULE_DAMAGE_GUARANTEE)
	assert_array(_tuning.damage_effect_ids).contains(["damage_single", "damage_single_heavy", "damage_all"])
	assert_bool(_tuning.is_valid()).is_true()


func test_damage_guarantee_gives_every_drafted_bot_a_damage_skill() -> void:
	_tuning.draft_rule = BotTuning.DRAFT_RULE_DAMAGE_GUARANTEE
	for seed_value in range(1, 41):
		for bot in _factory.build_draft(seed_value):
			assert_bool(_has_damage_skill(bot, _tuning)).is_true()
			assert_int(bot.skills.size()).is_equal(_tuning.starting_skill_count)
			assert_array(_tuning.validation_errors_for(bot)).is_empty()


func test_the_random_rule_can_draft_a_bot_with_no_damage_skill() -> void:
	_tuning.draft_rule = BotTuning.DRAFT_RULE_RANDOM
	var found := false
	for seed_value in range(1, 41):
		for bot in _factory.build_draft(seed_value):
			found = found or not _has_damage_skill(bot, _tuning)
	assert_bool(found).is_true()


func test_damage_guarantee_changes_only_skills_of_bots_that_drew_no_damage() -> void:
	_tuning.draft_rule = BotTuning.DRAFT_RULE_RANDOM
	var random_draft := _factory.build_draft(11)
	_tuning.draft_rule = BotTuning.DRAFT_RULE_DAMAGE_GUARANTEE
	var guaranteed := _factory.build_draft(11)
	for i in random_draft.size():
		var a := random_draft[i]
		var b := guaranteed[i]
		# Stats, names and personality are the same: the rule draws no randomness.
		assert_str(b.display_name).is_equal(a.display_name)
		assert_object(b.stats).is_equal(a.stats)
		assert_float(b.personality.aggressive_defensive).is_equal(a.personality.aggressive_defensive)
		var names_a := a.skills.map(func(s: Skill) -> String: return s.display_name)
		var names_b := b.skills.map(func(s: Skill) -> String: return s.display_name)
		if _has_damage_skill(a, _tuning):
			assert_array(names_b).is_equal(names_a)
		else:
			# The first skill drawn stays; the last becomes a damage skill.
			assert_str(names_b[0]).is_equal(names_a[0])
			assert_bool(_tuning.is_damage_skill(b.skills[-1])).is_true()


func test_an_unknown_draft_rule_is_rejected() -> void:
	_tuning.draft_rule = "best_of_three"
	assert_bool(_tuning.is_valid()).is_false()


func test_damage_guarantee_needs_a_damage_skill_in_the_catalog() -> void:
	_tuning.draft_rule = BotTuning.DRAFT_RULE_DAMAGE_GUARANTEE
	_tuning.damage_effect_ids = ["no_such_effect"]
	assert_bool(_tuning.is_valid()).is_false()
