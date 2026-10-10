extends GdUnitTestSuite


func test_holds_name_effect_cost_and_level() -> void:
	var skill := Skill.new("Arc Sweep", "damage_all", 6, 2)
	assert_str(skill.display_name).is_equal("Arc Sweep")
	assert_str(skill.effect_id).is_equal("damage_all")
	assert_int(skill.energy_cost).is_equal(6)
	assert_int(skill.level).is_equal(2)
	assert_bool(skill.is_valid()).is_true()


func test_defaults_to_level_one() -> void:
	assert_int(Skill.new("Strike", "damage_single", 0).level).is_equal(1)


func test_cost_is_flat_across_levels() -> void:
	var skill := Skill.new("Arc Sweep", "damage_all", 6, 1)
	skill.level = 5
	assert_int(skill.energy_cost).is_equal(6)


func test_invalid_skills_are_reported() -> void:
	assert_bool(Skill.new("", "damage_all", 6).is_valid()).is_false()
	assert_bool(Skill.new("Arc Sweep", "", 6).is_valid()).is_false()
	assert_bool(Skill.new("Arc Sweep", "damage_all", -1).is_valid()).is_false()
	assert_bool(Skill.new("Arc Sweep", "damage_all", 6, 0).is_valid()).is_false()


func test_a_bot_holds_skills_at_its_own_levels() -> void:
	var tuning := BotTuning.load_default()
	var bots := BotFactory.new(tuning).build_draft(3)
	bots[0].skills[0].level = 4
	assert_int(bots[0].skills[0].level).is_equal(4)
	for other in bots.slice(1):
		for skill in other.skills:
			assert_int(skill.level).is_equal(tuning.starting_skill_level)


func test_costs_come_from_the_catalog_definition() -> void:
	var tuning := BotTuning.load_default()
	var catalog := {}
	for skill in tuning.skills:
		catalog[skill.display_name] = skill
	for bot in BotFactory.new(tuning).build_draft(3):
		for skill in bot.skills:
			assert_bool(catalog.has(skill.display_name)).is_true()
			assert_int(skill.energy_cost).is_equal(catalog[skill.display_name].energy_cost)
			assert_str(skill.effect_id).is_equal(catalog[skill.display_name].effect_id)


func test_a_bot_with_a_skill_twice_is_invalid() -> void:
	var skills: Array[Skill] = [Skill.new("Strike", "damage_single", 0), Skill.new("Strike", "damage_single", 0)]
	assert_bool(Bot.new("b1", "Bolt", UnitStats.new(30, 8, 3, 7, 2, 10), null, skills).is_valid()).is_false()


func test_a_bot_with_an_invalid_skill_is_invalid() -> void:
	var skills: Array[Skill] = [Skill.new("Strike", "", 0)]
	assert_bool(Bot.new("b1", "Bolt", UnitStats.new(30, 8, 3, 7, 2, 10), null, skills).is_valid()).is_false()


func test_round_trips_through_a_file() -> void:
	var path := create_temp_dir("bot_data").path_join("skill.tres")
	assert_int(ResourceSaver.save(Skill.new("Patch Up", "heal_single", 3, 2), path)).is_equal(OK)
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Skill
	assert_str(loaded.display_name).is_equal("Patch Up")
	assert_str(loaded.effect_id).is_equal("heal_single")
	assert_int(loaded.energy_cost).is_equal(3)
	assert_int(loaded.level).is_equal(2)
