extends GdUnitTestSuite

const Snapshot := preload("res://tests/bot_data/resource_snapshot.gd")

var _builder: Control
var _dir: String
var _test_number := 0


func before_test() -> void:
	# Temp dirs last for the whole suite, so each test gets its own.
	_test_number += 1
	_dir = create_temp_dir("bot_builder_%d" % _test_number)
	_builder = auto_free(load("res://ui/dev/bot_builder.tscn").instantiate())
	_builder.bot_dir = _dir.path_join("bots")
	_builder.enemy_dir = _dir.path_join("enemies")
	add_child(_builder)


func _fill_form() -> void:
	_builder._id_edit.text = "hammer"
	_builder._name_edit.text = "Hammer"
	_builder._stat_spins["hp"].value = 38
	_builder._stat_spins["attack"].value = 9
	_builder._stat_spins["speed"].value = 12
	_builder._hp_spin.value = 30
	_builder._skill_rows["Patch Up"][0].button_pressed = true
	_builder._skill_rows["Strike"][0].button_pressed = true
	_builder._skill_rows["Strike"][1].value = 3


func test_a_saved_bot_loads_back_with_the_same_values() -> void:
	_fill_form()
	var made: Bot = _builder.bot_from_form()
	assert_int(_builder.save()).is_equal(OK)
	var loaded := BotLibrary.load_bot(BotLibrary.path_for(_builder.bot_dir, "hammer"))
	assert_that(Snapshot.of(loaded)).is_equal(Snapshot.of(made))
	assert_int(loaded.stats.attack).is_equal(9)
	assert_int(loaded.hp).is_equal(30)
	var levels := {}
	for s in loaded.skills:
		levels[s.display_name] = s.level
	assert_int(levels["Strike"]).is_equal(3)
	assert_bool(levels.has("Patch Up")).is_true()


func test_loading_a_file_fills_the_form_with_its_values() -> void:
	_fill_form()
	_builder.save()
	var saved: Bot = _builder.bot_from_form()
	_builder.new_bot()
	assert_str(_builder._id_edit.text).is_not_equal("hammer")
	assert_bool(_builder.load_file(BotLibrary.path_for(_builder.bot_dir, "hammer"))).is_true()
	assert_that(Snapshot.of(_builder.bot_from_form())).is_equal(Snapshot.of(saved))


func test_editing_a_loaded_bot_and_saving_overwrites_it() -> void:
	_fill_form()
	_builder.save()
	_builder.load_file(BotLibrary.path_for(_builder.bot_dir, "hammer"))
	_builder._stat_spins["defense"].value = 7
	_builder.save()
	assert_int(BotLibrary.load_bot(BotLibrary.path_for(_builder.bot_dir, "hammer")).stats.defense).is_equal(7)
	assert_int(BotLibrary.list(_builder.bot_dir).size()).is_equal(1)
	assert_int(_builder._library.item_count).is_equal(1)


func test_an_invalid_bot_is_not_saved() -> void:
	_fill_form()
	_builder._id_edit.text = ""
	assert_int(_builder.save()).is_equal(ERR_INVALID_DATA)
	assert_array(BotLibrary.list(_builder.bot_dir)).is_empty()
	assert_str(_builder._status.text).contains("Not saved")


func test_enemies_save_to_their_own_folder() -> void:
	_builder.set_role(_builder.Role.ENEMY)
	_builder.new_bot()
	assert_str(_builder._id_edit.text).starts_with("enemy_")
	assert_int(_builder.save()).is_equal(OK)
	assert_int(BotLibrary.list(_builder.enemy_dir).size()).is_equal(1)
	assert_array(BotLibrary.list(_builder.bot_dir)).is_empty()


func test_stats_outside_the_tuning_warn_but_still_save() -> void:
	_fill_form()
	_builder._stat_spins["speed"].value = 60
	assert_str(_builder._problems.text).contains("Outside the draft tuning")
	assert_int(_builder.save()).is_equal(OK)


## Personality: six ends edited on the form, saved and loaded with the bot.
func test_personality_ends_save_and_load() -> void:
	_fill_form()
	_builder._end_spins["aggressive"].value = 1.25
	_builder._end_spins["defensive"].value = 0.5
	_builder._end_spins["methodical"].value = 0.75
	_builder._generation_spin.value = 2
	var made: Bot = _builder.bot_from_form()
	assert_array(made.personality.get_ends()).is_equal([1.25, 0.5, 0.0, 0.0, 0.0, 0.75])
	assert_int(_builder.save()).is_equal(OK)
	var loaded := BotLibrary.load_bot(BotLibrary.path_for(_builder.bot_dir, "hammer"))
	assert_array(loaded.personality.get_ends()).is_equal([1.25, 0.5, 0.0, 0.0, 0.0, 0.75])
	assert_int(loaded.personality.generation).is_equal(2)
	_builder.show_bot(loaded)
	assert_float(_builder._end_spins["aggressive"].value).is_equal(1.25)
	assert_array(_builder._hexagon.after).is_equal(loaded.personality.get_ends())


func test_bot_json_keeps_the_personality() -> void:
	var tuning := BotTuning.load_default()
	var bot := BotLibrary.new_bot(tuning, "j", "J")
	bot.personality.supportive = 0.8
	bot.personality.solitary = 0.3
	var problems: Array[String] = []
	var back := BotJson.from_dict(BotJson.to_dict(bot), tuning, problems)
	assert_array(problems).is_empty()
	assert_array(back.personality.get_ends()).is_equal(bot.personality.get_ends())
