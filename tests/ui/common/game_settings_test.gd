extends GdUnitTestSuite
## GameSettings: defaults, saving between runs, and what each setting does.

var _path := ""


func before_test() -> void:
	_path = "user://test_settings_%d.cfg" % Time.get_ticks_usec()


func after_test() -> void:
	DirAccess.remove_absolute(_path)


func test_starts_from_the_data_defaults() -> void:
	var s := GameSettings.new()
	var defaults: Dictionary = FeelData.settings()["defaults"]
	assert_float(s.music_volume).is_equal_approx(defaults["music_volume"], 0.001)
	assert_bool(s.shake_enabled).is_equal(defaults["shake_enabled"])
	assert_str(s.animation_speed).is_equal(defaults["animation_speed"])


func test_choices_survive_a_save_and_reload() -> void:
	var s := GameSettings.new()
	s.load_from(_path)
	s.set_value("effects_volume", 0.25)
	s.set_value("reduced_motion", true)
	s.set_value("animation_speed", "2x")
	var again := GameSettings.new()
	again.load_from(_path)
	assert_float(again.effects_volume).is_equal_approx(0.25, 0.001)
	assert_bool(again.reduced_motion).is_true()
	assert_str(again.animation_speed).is_equal("2x")


func test_bad_values_are_clamped_or_ignored() -> void:
	var s := GameSettings.new()
	s.set_value("music_volume", 7.0)
	s.set_value("animation_speed", "9x")
	assert_float(s.music_volume).is_equal(1.0)
	assert_str(s.animation_speed).is_equal("1x")


func test_animation_speed_scales_durations() -> void:
	var s := GameSettings.new()
	s.animation_speed = "2x"
	assert_float(s.scale_seconds(0.4)).is_equal_approx(0.2, 0.0001)
	s.animation_speed = "1.5x"
	assert_float(s.scale_seconds(0.3)).is_equal_approx(0.2, 0.0001)
	s.animation_speed = "skip"
	assert_float(s.scale_seconds(0.4)).is_equal(0.0)
	assert_bool(s.skips_animations()).is_true()


func test_shake_is_zero_when_off_or_motion_is_reduced() -> void:
	var s := GameSettings.new()
	s.shake_strength = 0.5
	assert_float(s.shake_scale()).is_equal(0.5)
	s.reduced_motion = true
	assert_float(s.shake_scale()).is_equal(0.0)
	s.reduced_motion = false
	s.shake_enabled = false
	assert_float(s.shake_scale()).is_equal(0.0)


func test_volumes_reach_the_audio_buses() -> void:
	var s := GameSettings.new()
	s.music_volume = 0.5
	s.interface_volume = 0.0
	s.apply_to_buses()
	var music := AudioServer.get_bus_index("Music")
	var ui := AudioServer.get_bus_index("Interface")
	assert_int(music).is_greater(0)
	assert_float(AudioServer.get_bus_volume_db(music)).is_equal_approx(linear_to_db(0.5), 0.01)
	assert_bool(AudioServer.is_bus_mute(ui)).is_true()
	GameSettings.new().apply_to_buses()


func test_changes_notify_listeners() -> void:
	var s := GameSettings.new()
	var seen := []
	s.changed.connect(func() -> void: seen.append(true))
	s.set_value("shake_enabled", false)
	assert_int(seen.size()).is_equal(1)
