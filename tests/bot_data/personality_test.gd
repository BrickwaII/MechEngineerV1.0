extends GdUnitTestSuite


func test_defaults_to_generation_one_and_no_lean() -> void:
	var personality := Personality.new()
	assert_int(personality.generation).is_equal(1)
	for scale in Personality.SCALE_COUNT:
		assert_float(personality.get_raw_value(scale)).is_equal(0.0)


func test_values_clamp_to_minus_one_and_one() -> void:
	var personality := Personality.new(3, -2.0, 1.5, 0.25)
	assert_float(personality.aggressive_defensive).is_equal(-1.0)
	assert_float(personality.solitary_supportive).is_equal(1.0)
	assert_float(personality.reactive_methodical).is_equal(0.25)
	personality.reactive_methodical = 7.0
	assert_float(personality.reactive_methodical).is_equal(1.0)
	assert_bool(personality.is_valid()).is_true()


func test_generation_never_drops_below_one() -> void:
	assert_int(Personality.new(0).generation).is_equal(1)
	assert_int(Personality.new(-4).generation).is_equal(1)


func test_generation_decides_how_many_scales_are_active() -> void:
	assert_int(Personality.new(1).get_active_scale_count()).is_equal(1)
	assert_int(Personality.new(2).get_active_scale_count()).is_equal(2)
	assert_int(Personality.new(3).get_active_scale_count()).is_equal(3)
	assert_int(Personality.new(9).get_active_scale_count()).is_equal(3)


func test_scales_activate_in_order() -> void:
	var gen2 := Personality.new(2)
	assert_bool(gen2.is_active(Personality.Scale.AGGRESSIVE_DEFENSIVE)).is_true()
	assert_bool(gen2.is_active(Personality.Scale.SOLITARY_SUPPORTIVE)).is_true()
	assert_bool(gen2.is_active(Personality.Scale.REACTIVE_METHODICAL)).is_false()


func test_an_inactive_scale_reads_as_zero_but_keeps_its_value() -> void:
	var personality := Personality.new(1, 0.4, 0.8, -0.6)
	assert_float(personality.get_value(Personality.Scale.AGGRESSIVE_DEFENSIVE)).is_equal(0.4)
	assert_float(personality.get_value(Personality.Scale.SOLITARY_SUPPORTIVE)).is_equal(0.0)
	assert_float(personality.get_raw_value(Personality.Scale.SOLITARY_SUPPORTIVE)).is_equal(0.8)
	personality.generation = 3
	assert_float(personality.get_value(Personality.Scale.REACTIVE_METHODICAL)).is_equal(-0.6)


func test_tag_names_the_strongest_active_pole() -> void:
	assert_str(Personality.new(1, -0.3).get_tag()).is_equal("aggressive")
	assert_str(Personality.new(1, 0.3).get_tag()).is_equal("defensive")
	assert_str(Personality.new(2, 0.1, 0.5).get_tag()).is_equal("supportive")
	assert_str(Personality.new(3, 0.1, -0.2, -0.9).get_tag()).is_equal("reactive")
	assert_str(Personality.new(3, 0.0, 0.0, 0.7).get_tag()).is_equal("methodical")
	assert_str(Personality.new(2, 0.0, -0.4).get_tag()).is_equal("solitary")


func test_tag_ignores_inactive_scales() -> void:
	assert_str(Personality.new(1, 0.1, 0.9, 0.9).get_tag()).is_equal("defensive")


func test_tag_is_balanced_with_no_lean_and_earlier_scale_wins_a_tie() -> void:
	assert_str(Personality.new(3).get_tag()).is_equal(Personality.BALANCED_TAG)
	assert_str(Personality.new(2, 0.5, -0.5).get_tag()).is_equal("defensive")


func test_round_trips_through_a_file() -> void:
	var path := create_temp_dir("bot_data").path_join("personality.tres")
	assert_int(ResourceSaver.save(Personality.new(2, -0.75, 0.5, 0.25), path)).is_equal(OK)
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Personality
	assert_int(loaded.generation).is_equal(2)
	assert_float(loaded.aggressive_defensive).is_equal(-0.75)
	assert_float(loaded.solitary_supportive).is_equal(0.5)
	assert_float(loaded.reactive_methodical).is_equal(0.25)


func test_out_of_range_values_in_a_file_are_clamped_on_load() -> void:
	var path := create_temp_dir("bot_data").path_join("personality.tres")
	assert_int(ResourceSaver.save(Personality.new(3, 0.5), path)).is_equal(OK)
	var text := FileAccess.get_file_as_string(path).replace("aggressive_defensive = 0.5", "aggressive_defensive = 4.0")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Personality
	assert_float(loaded.aggressive_defensive).is_equal(1.0)
