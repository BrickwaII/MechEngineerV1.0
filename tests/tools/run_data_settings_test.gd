extends GdUnitTestSuite


func test_the_data_file_loads() -> void:
	var s := RunDataSettings.load_default()
	assert_array(s.errors).is_empty()
	assert_str(s.runs_folder).is_equal("user://runs")
	assert_array(Array(s.feedback_categories)).is_equal(["bug", "balance", "UI", "idea", "other"])
	assert_int(s.mood_min).is_equal(1)
	assert_int(s.mood_max).is_equal(5)
	assert_float(s.act_target_minutes.x).is_equal(10.0)
	assert_float(s.act_target_minutes.y).is_equal(30.0)
