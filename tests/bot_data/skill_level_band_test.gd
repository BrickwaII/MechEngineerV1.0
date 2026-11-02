extends GdUnitTestSuite
## A bot's generation band (Bot.skill_level_band), stored for the combat
## rework's generation caps (S15). Nothing caps a level by it yet.


func _bot() -> Bot:
	return Bot.new("b", "B", UnitStats.new(30, 5, 3, 5, 2, 10))


func test_a_new_bot_has_an_open_band() -> void:
	assert_that(_bot().skill_level_band).is_equal(Vector2i(Skill.MIN_LEVEL, Bot.NO_LEVEL_CAP))
	assert_bool(_bot().is_valid()).is_true()


func test_a_drafted_bot_takes_the_tuning_band() -> void:
	var tuning := BotTuning.load_default()
	for bot in BotFactory.new(tuning).build_draft(7):
		assert_that(bot.skill_level_band).is_equal(tuning.starting_skill_level_band)
		assert_array(tuning.validation_errors_for(bot)).is_empty()


func test_a_bad_band_is_invalid() -> void:
	var bot := _bot()
	bot.skill_level_band = Vector2i(0, 5)
	assert_bool(bot.is_valid()).is_false()
	bot.skill_level_band = Vector2i(5, 3)
	assert_bool(bot.is_valid()).is_false()
	bot.skill_level_band = Vector2i(3, 7)
	assert_bool(bot.is_valid()).is_true()


func test_a_band_survives_a_save() -> void:
	var squad := BotFactory.new(BotTuning.load_default()).build_squad(2024)
	squad.bots[0].skill_level_band = Vector2i(3, 7)
	var path := create_temp_dir("band_save").path_join("squad.tres")
	assert_int(BotSquadStorage.save_squad(squad, path)).is_equal(OK)
	var loaded := BotSquadStorage.load_squad(path)
	assert_that(loaded.bots[0].skill_level_band).is_equal(Vector2i(3, 7))
	assert_that(loaded.bots[1].skill_level_band).is_equal(Vector2i(1, Bot.NO_LEVEL_CAP))


func test_a_save_from_before_the_band_loads_with_the_open_band() -> void:
	# A default band is not written, so a save made before the field existed
	# reads exactly like one made now.
	var squad := BotFactory.new(BotTuning.load_default()).build_squad(2024)
	var path := create_temp_dir("band_old_save").path_join("squad.tres")
	assert_int(BotSquadStorage.save_squad(squad, path)).is_equal(OK)
	assert_str(FileAccess.get_file_as_string(path)).not_contains("skill_level_band")
	var loaded := BotSquadStorage.load_squad(path)
	for bot in loaded.bots:
		assert_that(bot.skill_level_band).is_equal(Vector2i(1, Bot.NO_LEVEL_CAP))
