extends GdUnitTestSuite
## Personality: three spectrums, two ends each, ends only ever >= 0.
const Legacy := preload("res://tests/fight/legacy_switches.gd")


func test_defaults_to_generation_one_and_no_lean() -> void:
	var personality := Personality.new()
	assert_int(personality.generation).is_equal(1)
	for pole in Personality.ENDS:
		assert_float(personality.get_end(pole)).is_equal(0.0)
	for scale in Personality.SCALE_COUNT:
		assert_float(personality.get_net(scale)).is_equal(0.0)


func test_a_signed_value_splits_onto_the_two_ends() -> void:
	var p := Personality.new(3, -0.4, 0.7, 0.0)
	assert_float(p.aggressive).is_equal_approx(0.4, 1e-6)
	assert_float(p.defensive).is_equal(0.0)
	assert_float(p.solitary).is_equal(0.0)
	assert_float(p.supportive).is_equal_approx(0.7, 1e-6)
	assert_float(p.reactive).is_equal(0.0)
	assert_float(p.methodical).is_equal(0.0)
	assert_float(p.aggressive_defensive).is_equal_approx(-0.4, 1e-6)


func test_ends_never_go_below_zero_and_have_no_cap() -> void:
	var p := Personality.new()
	p.aggressive = -3.0
	assert_float(p.aggressive).is_equal(0.0)
	p.defensive = 12.5
	assert_float(p.defensive).is_equal(12.5)
	assert_bool(p.is_valid()).is_true()


func test_both_ends_hold_values_and_the_net_is_their_difference() -> void:
	var p := Personality.new()
	p.aggressive = 1.5
	p.defensive = 0.5
	assert_float(p.get_net(Personality.Scale.AGGRESSIVE_DEFENSIVE)).is_equal_approx(-1.0, 1e-6)
	assert_float(p.get_end("aggressive")).is_equal(1.5)
	assert_float(p.get_end("grumpy")).is_equal(0.0)
	assert_array(p.get_ends()).is_equal([1.5, 0.5, 0.0, 0.0, 0.0, 0.0])


func test_lean_is_the_plain_net_below_the_floor_and_the_winning_share_above_it() -> void:
	var p := Personality.new(3, -0.6)
	assert_float(p.get_lean(Personality.Scale.AGGRESSIVE_DEFENSIVE, 1.0)).is_equal_approx(-0.6, 1e-6)
	p.aggressive = 3.0
	p.defensive = 1.0
	# (1 - 3) / (3 + 1)
	assert_float(p.get_lean(Personality.Scale.AGGRESSIVE_DEFENSIVE, 1.0)).is_equal_approx(-0.5, 1e-6)
	p.defensive = 3.0
	assert_float(p.get_lean(Personality.Scale.AGGRESSIVE_DEFENSIVE, 1.0)).is_equal(0.0)
	p.aggressive = 100.0
	p.defensive = 0.0
	assert_float(p.get_lean(Personality.Scale.AGGRESSIVE_DEFENSIVE, 1.0)).is_equal(-1.0)


func test_generation_never_drops_below_one() -> void:
	assert_int(Personality.new(0).generation).is_equal(1)
	assert_int(Personality.new(-4).generation).is_equal(1)


func test_generation_decides_how_many_spectrums_the_planner_weighs() -> void:
	assert_int(Personality.new(1).get_active_scale_count()).is_equal(1)
	assert_int(Personality.new(2).get_active_scale_count()).is_equal(2)
	assert_int(Personality.new(3).get_active_scale_count()).is_equal(3)
	assert_int(Personality.new(9).get_active_scale_count()).is_equal(3)
	var gen2 := Personality.new(2)
	assert_bool(gen2.is_active(Personality.Scale.SOLITARY_SUPPORTIVE)).is_true()
	assert_bool(gen2.is_active(Personality.Scale.REACTIVE_METHODICAL)).is_false()


func test_tag_names_the_end_with_the_strongest_lean_on_any_spectrum() -> void:
	assert_str(Personality.new(1, -0.3).get_tag()).is_equal("aggressive")
	assert_str(Personality.new(1, 0.3).get_tag()).is_equal("defensive")
	assert_str(Personality.new(2, 0.1, 0.5).get_tag()).is_equal("supportive")
	assert_str(Personality.new(3, 0.1, -0.2, -0.9).get_tag()).is_equal("reactive")
	assert_str(Personality.new(3, 0.0, 0.0, 0.7).get_tag()).is_equal("methodical")
	# Every spectrum grows from generation 1, so every spectrum can name the tag.
	assert_str(Personality.new(1, 0.1, 0.9).get_tag()).is_equal("supportive")


func test_tag_is_balanced_with_no_lean_and_earlier_spectrum_wins_a_tie() -> void:
	assert_str(Personality.new(3).get_tag()).is_equal(Personality.BALANCED_TAG)
	assert_str(Personality.new(2, 0.5, -0.5).get_tag()).is_equal("defensive")
	var even := Personality.new()
	even.aggressive = 2.0
	even.defensive = 2.0
	assert_str(even.get_tag()).is_equal(Personality.BALANCED_TAG)


func test_round_trips_through_a_file() -> void:
	var path := create_temp_dir("bot_data").path_join("personality.tres")
	var p := Personality.new(2)
	p.aggressive = 1.75
	p.defensive = 0.5
	p.methodical = 0.25
	assert_int(ResourceSaver.save(p, path)).is_equal(OK)
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Personality
	assert_int(loaded.generation).is_equal(2)
	assert_array(loaded.get_ends()).is_equal([1.75, 0.5, 0.0, 0.0, 0.0, 0.25])


## Save format 1 kept one signed value per spectrum; it splits as it loads:
## v becomes max(-v, 0) on the first end and max(v, 0) on the second.
func test_a_format_one_file_converts_as_it_loads() -> void:
	var path := create_temp_dir("bot_data").path_join("old_personality.tres")
	var text := "\n".join([
		'[gd_resource type="Resource" script_class="Personality" format=3]',
		'',
		'[ext_resource type="Script" path="res://bot_data/personality.gd" id="1"]',
		'',
		'[resource]',
		'script = ExtResource("1")',
		'generation = 2',
		'aggressive_defensive = -1.0',
		'solitary_supportive = 0.35',
		''])
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Personality
	assert_int(loaded.generation).is_equal(2)
	assert_array(loaded.get_ends()).is_equal([1.0, 0.0, 0.0, 0.35, 0.0, 0.0])
	assert_bool(loaded.is_valid()).is_true()
	# A save written now holds the ends only.
	var path2 := path.get_base_dir().path_join("new_personality.tres")
	ResourceSaver.save(loaded, path2)
	var saved := FileAccess.get_file_as_string(path2)
	assert_str(saved).contains("aggressive = 1.0")
	assert_str(saved).not_contains("aggressive_defensive")


## These tests' numbers were worked out under the old fight switches.
func before() -> void:
	Legacy.pin()


func after() -> void:
	Legacy.unpin()

