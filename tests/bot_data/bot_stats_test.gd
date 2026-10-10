extends GdUnitTestSuite
## The six-stat record: bots reuse contracts/UnitStats, and bot_data validates it.


func _script_storage_names(script: Script) -> Array[String]:
	var found: Array[String] = []
	for property in script.get_script_property_list():
		if property.usage & PROPERTY_USAGE_STORAGE:
			found.append(property.name)
	return found


func test_stat_names_are_exactly_the_unit_stats_fields() -> void:
	assert_array(_script_storage_names(UnitStats)).contains_exactly(Bot.STAT_NAMES)


func test_efficiency_is_not_a_stat() -> void:
	assert_array(Bot.STAT_NAMES).not_contains(["efficiency"])
	assert_bool("efficiency" in UnitStats.new()).is_false()


func test_a_bot_holds_unit_stats() -> void:
	var bot := Bot.new("b1", "Bolt", UnitStats.new(30, 8, 3, 7, 2, 10))
	assert_object(bot.stats).is_instanceof(UnitStats)
	assert_int(bot.stats.elasticity).is_equal(2)
	assert_int(bot.stats.battery_capacity).is_equal(10)


func test_a_new_bot_starts_at_full_hp() -> void:
	var bot := Bot.new("b1", "Bolt", UnitStats.new(30, 8, 3, 7, 2, 10))
	assert_int(bot.hp).is_equal(30)
	assert_int(bot.get_max_hp()).is_equal(30)


func test_a_complete_bot_is_valid() -> void:
	assert_array(Bot.new("b1", "Bolt", UnitStats.new(30, 8, 3, 7, 2, 10)).validation_errors()).is_empty()


func test_a_negative_stat_is_invalid() -> void:
	var bot := Bot.new("b1", "Bolt", UnitStats.new(30, 8, -1, 7, 2, 10))
	assert_bool(bot.is_valid()).is_false()


func test_zero_max_hp_is_invalid() -> void:
	assert_bool(Bot.new("b1", "Bolt", UnitStats.new(0, 8, 3, 7, 2, 10)).is_valid()).is_false()


func test_current_hp_above_max_is_invalid() -> void:
	var bot := Bot.new("b1", "Bolt", UnitStats.new(30, 8, 3, 7, 2, 10))
	bot.hp = 31
	assert_bool(bot.is_valid()).is_false()
	bot.hp = 0
	assert_bool(bot.is_valid()).is_true()


func test_a_bot_needs_an_id_and_a_name() -> void:
	assert_bool(Bot.new("", "Bolt", UnitStats.new(30, 8, 3, 7, 2, 10)).is_valid()).is_false()
	assert_bool(Bot.new("b1", "", UnitStats.new(30, 8, 3, 7, 2, 10)).is_valid()).is_false()


func test_tuning_rejects_a_stat_outside_its_range() -> void:
	var tuning := BotTuning.load_default()
	var high := tuning.stat_ranges["attack"].y
	var bot := BotFactory.new(tuning).build_draft(1)[0]
	assert_array(tuning.validation_errors_for(bot)).is_empty()
	bot.stats.attack = high + 1
	assert_array(tuning.validation_errors_for(bot)).has_size(1)


func test_to_summary_copies_identity_hp_and_stats() -> void:
	var bot := Bot.new("b1", "Bolt", UnitStats.new(30, 8, 3, 7, 2, 10), Personality.new(1, -0.5))
	bot.hp = 12
	var summary := bot.to_summary()
	assert_str(summary.id).is_equal("b1")
	assert_str(summary.display_name).is_equal("Bolt")
	assert_int(summary.hp).is_equal(12)
	assert_int(summary.max_hp).is_equal(30)
	assert_str(summary.personality_tag).is_equal("aggressive")
	assert_int(summary.stats.speed).is_equal(7)


func test_changing_a_summary_does_not_change_the_bot() -> void:
	var bot := Bot.new("b1", "Bolt", UnitStats.new(30, 8, 3, 7, 2, 10))
	bot.to_summary().stats.attack = 99
	assert_int(bot.stats.attack).is_equal(8)


func test_stats_round_trip_through_a_file() -> void:
	var path := create_temp_dir("bot_data").path_join("bot.tres")
	assert_int(ResourceSaver.save(Bot.new("b1", "Bolt", UnitStats.new(30, 8, 3, 7, 2, 10)), path)).is_equal(OK)
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as Bot
	for stat in Bot.STAT_NAMES:
		assert_int(loaded.stats.get(stat)).is_equal([30, 8, 3, 7, 2, 10][Bot.STAT_NAMES.find(stat)])
