extends GdUnitTestSuite


func test_holds_six_integer_stats_in_order() -> void:
	var stats := UnitStats.new(30, 8, 3, 7, 2, 10)
	assert_array([stats.hp, stats.attack, stats.defense, stats.speed, stats.elasticity, stats.battery_capacity]) \
		.contains_exactly([30, 8, 3, 7, 2, 10])


func test_defaults_to_zero() -> void:
	var stats := UnitStats.new()
	assert_int(stats.hp + stats.attack + stats.defense + stats.speed + stats.elasticity + stats.battery_capacity) \
		.is_zero()


func test_round_trips_through_a_resource_file() -> void:
	var path := create_temp_dir("contracts").path_join("stats.tres")
	assert_int(ResourceSaver.save(UnitStats.new(30, 8, 3, 7, 2, 10), path)).is_equal(OK)
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as UnitStats
	assert_object(loaded).is_not_null()
	assert_int(loaded.battery_capacity).is_equal(10)
	assert_int(loaded.elasticity).is_equal(2)
