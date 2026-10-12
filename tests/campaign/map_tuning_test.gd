extends GdUnitTestSuite

const TUNING := "res://data/tuning/overworld.json"


func test_shipped_tuning_loads_with_the_stated_numbers() -> void:
	var t := MapTuning.load_file(TUNING)
	assert_array(t.errors).is_empty()
	assert_int(t.points_per_day).is_equal(4)
	assert_int(t.total_points).is_equal(400)
	assert_int(t.attack_time).is_equal(3)
	assert_int(t.reinforce_time).is_equal(1)
	assert_int(t.wait_time).is_equal(1)
	assert_float(t.pressure_rate_base).is_equal(0.6)
	assert_float(t.pressure_rate_per_base).is_equal(0.6)
	assert_float(t.border_multiplier).is_equal(1.5)
	assert_float(t.forces_defense_at).is_equal(100.0)
	assert_float(t.reinforce_relief).is_equal(45.0)
	assert_float(t.grid_regen_divisor).is_equal(4.0)
	assert_float(t.attack_grid_base).is_equal(4.0)
	assert_float(t.attack_grid_per_defense).is_equal(2.0)
	assert_float(t.defeat_grid_multiplier).is_equal(1.5)
	assert_int(t.defense_levels.size()).is_equal(6)
	assert_str(t.defense_label(5)).is_equal("Fortified")
	assert_str(t.rate_word(1.8)).is_equal("steadily")
	assert_str(t.rate_word(1.2)).is_equal("slowly")
	assert_str(t.rate_word(4.05)).is_equal("quickly")


func test_a_missing_key_is_an_error() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TUNING))
	(data["grid"] as Dictionary).erase("defeat_multiplier")
	var t := MapTuning.from_dict(data)
	assert_array(t.errors).contains(["tuning is missing 'grid.defeat_multiplier'"])


func test_shipped_tuning_has_the_view_and_boss_numbers() -> void:
	var t := MapTuning.load_file(TUNING)
	assert_float(t.pressure_scale).is_equal(1.0)
	assert_int(t.boss_defense_level).is_equal(5)
	assert_str(t.node_style).is_equal(MapTuning.NODE_FULL)
	assert_float(t.globe_size).is_greater(0.0)
	assert_float(t.globe_edge_degrees).is_greater(0.0)


func test_an_act_file_lays_its_numbers_over_its_base() -> void:
	var base := MapTuning.load_file(TUNING)
	var act2 := MapTuning.load_file("res://data/tuning/act2.json")
	assert_array(act2.errors).is_empty()
	assert_int(act2.total_points).is_equal(400)
	assert_int(act2.pressure_reference_regions).is_equal(19)
	assert_int(base.pressure_reference_regions).is_equal(0)
	assert_str(act2.node_style).is_equal(MapTuning.NODE_COMPACT)
	# Everything else comes from the base, nested keys included.
	assert_int(act2.points_per_day).is_equal(base.points_per_day)
	assert_int(act2.attack_time).is_equal(base.attack_time)
	assert_float(act2.forces_defense_at).is_equal(base.forces_defense_at)
	assert_float(act2.globe_size).is_equal(base.globe_size)
	assert_int(act2.defense_levels.size()).is_equal(6)


func test_a_bad_base_is_an_error() -> void:
	var path := "user://map_tuning_test_loop.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"base": path, "time": {"total_points": 1}}))
	file.close()
	assert_array(MapTuning.load_file(path).errors).contains(["tuning base loop at %s" % path])
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"base": "res://data/tuning/missing.json"}))
	file.close()
	assert_bool(MapTuning.load_file(path).is_valid()).is_false()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_a_bad_node_style_is_an_error() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TUNING))
	data["view"]["node_style"] = "huge"
	assert_bool(MapTuning.from_dict(data).is_valid()).is_false()
