extends GdUnitTestSuite

const Snapshot := preload("res://tests/bot_data/resource_snapshot.gd")

var _squad: BotSquad


func before_test() -> void:
	_squad = BotFactory.new(BotTuning.load_default()).build_squad(2024)
	# Mid-run state, so the round trip covers more than factory defaults.
	_squad.bots[0].hp -= 5
	_squad.bots[1].skills[0].level = 3
	_squad.bots[2].personality.generation = 3
	_squad.bots[2].personality.reactive_methodical = -0.4


func _path(file_name: String) -> String:
	return create_temp_dir("bot_data_save").path_join(file_name)


func test_a_squad_round_trips_through_a_text_file_unchanged() -> void:
	var path := _path("squad.tres")
	assert_int(BotSquadStorage.save_squad(_squad, path)).is_equal(OK)
	var loaded := BotSquadStorage.load_squad(path)
	assert_object(loaded).is_not_null()
	assert_that(Snapshot.of(loaded)).is_equal(Snapshot.of(_squad))


func test_a_squad_round_trips_through_a_binary_file_unchanged() -> void:
	var path := _path("squad.res")
	assert_int(BotSquadStorage.save_squad(_squad, path)).is_equal(OK)
	assert_that(Snapshot.of(BotSquadStorage.load_squad(path))).is_equal(Snapshot.of(_squad))


func test_the_loaded_squad_is_a_new_object_each_time() -> void:
	var path := _path("squad.tres")
	BotSquadStorage.save_squad(_squad, path)
	var first := BotSquadStorage.load_squad(path)
	first.bots[0].hp = 1
	assert_int(BotSquadStorage.load_squad(path).bots[0].hp).is_equal(_squad.bots[0].hp)


func test_a_saved_squad_survives_a_second_round_trip() -> void:
	var path := _path("squad.tres")
	BotSquadStorage.save_squad(_squad, path)
	var again := _path("again.tres")
	assert_int(BotSquadStorage.save_squad(BotSquadStorage.load_squad(path), again)).is_equal(OK)
	assert_that(Snapshot.of(BotSquadStorage.load_squad(again))).is_equal(Snapshot.of(_squad))


func test_an_invalid_squad_is_not_saved() -> void:
	_squad.bots[0].hp = -1
	var path := _path("bad.tres")
	assert_int(BotSquadStorage.save_squad(_squad, path)).is_equal(ERR_INVALID_DATA)
	assert_bool(FileAccess.file_exists(path)).is_false()


func test_a_missing_file_loads_as_null() -> void:
	assert_object(BotSquadStorage.load_squad(_path("nothing.tres"))).is_null()


func test_a_file_holding_something_else_loads_as_null() -> void:
	var path := _path("stats.tres")
	ResourceSaver.save(UnitStats.new(1, 1, 1, 1, 1, 1), path)
	assert_object(BotSquadStorage.load_squad(path)).is_null()
