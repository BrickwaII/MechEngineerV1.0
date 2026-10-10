extends GdUnitTestSuite

const H := preload("res://tests/tools/tools_test_helpers.gd")
const Snapshot := preload("res://tests/bot_data/resource_snapshot.gd")


func test_a_saved_bot_loads_back_with_the_same_values() -> void:
	var tuning := BotTuning.load_default()
	var dir := create_temp_dir("bot_library")
	var bot := BotLibrary.new_bot(tuning, "hammer", "Hammer")
	bot.stats.attack = 12
	bot.stats.battery_capacity = 3
	bot.hp = bot.stats.hp - 2
	bot.skills[0].level = 5
	bot.skills.append(BotJson.catalog_skill(tuning, "Patch Up").duplicate())
	assert_int(BotLibrary.save_bot(bot, dir, tuning)).is_equal(OK)
	var loaded := BotLibrary.load_bot(BotLibrary.path_for(dir, "hammer"))
	assert_object(loaded).is_not_null()
	assert_that(Snapshot.of(loaded)).is_equal(Snapshot.of(bot))


func test_the_file_is_a_squad_any_squad_reader_can_load() -> void:
	var tuning := H.bot_tuning()
	var dir := create_temp_dir("bot_library2")
	BotLibrary.save_bot(BotLibrary.new_bot(tuning, "a", "A"), dir, tuning)
	var squad := BotSquadStorage.load_squad(BotLibrary.path_for(dir, "a"))
	assert_array(squad.fielded_ids).is_equal(["a"])
	assert_int(BotSquadProvider.new(squad).get_squad().size()).is_equal(1)


func test_an_invalid_bot_is_not_saved() -> void:
	var tuning := H.bot_tuning()
	var dir := create_temp_dir("bot_library3")
	var bot := BotLibrary.new_bot(tuning, "", "Nameless id")
	assert_int(BotLibrary.save_bot(bot, dir, tuning)).is_equal(ERR_INVALID_DATA)
	assert_array(BotLibrary.list(dir)).is_empty()


func test_saving_again_overwrites_and_list_finds_each_bot_once() -> void:
	var tuning := H.bot_tuning()
	var dir := create_temp_dir("bot_library4")
	var bot := BotLibrary.new_bot(tuning, "b", "B")
	BotLibrary.save_bot(bot, dir, tuning)
	bot.stats.defense = 30
	BotLibrary.save_bot(bot, dir, tuning)
	BotLibrary.save_bot(BotLibrary.new_bot(tuning, "a", "A"), dir, tuning)
	assert_array(BotLibrary.list(dir)).is_equal([dir.path_join("a.tres"), dir.path_join("b.tres")])
	assert_int(BotLibrary.load_bot(dir.path_join("b.tres")).stats.defense).is_equal(30)


func test_a_new_bot_starts_valid_within_the_tuning() -> void:
	var tuning := BotTuning.load_default()
	var bot := BotLibrary.new_bot(tuning, "n", "N")
	assert_array(tuning.validation_errors_for(bot)).is_empty()


func test_the_dev_tool_settings_load() -> void:
	var s := DevToolSettings.load_default()
	assert_int(s.default_runs).is_greater(0)
	assert_str(s.stats_log_path).starts_with("user://")
	assert_int(s.overlay_timeline_count).is_greater(0)
