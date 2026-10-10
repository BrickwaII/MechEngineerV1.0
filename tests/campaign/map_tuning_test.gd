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
