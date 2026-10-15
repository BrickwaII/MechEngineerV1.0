extends GdUnitTestSuite
## The settings file: an old file migrates (a saved 100% from before version 2
## loads as Auto, so Fit window scaling applies), and tests and tools never
## read or write the player's own file.

var _path := ""
var _player_before := {}


func before() -> void:
	_player_before = _snapshot(GameSettings.player_path())


func after() -> void:
	# Whatever this suite did with the shared settings, the player's file is
	# as it was.
	assert_dict(_snapshot(GameSettings.player_path())).is_equal(_player_before)


func before_test() -> void:
	_path = "user://test_settings_file_%d.cfg" % Time.get_ticks_usec()


func after_test() -> void:
	DirAccess.remove_absolute(_path)


func _snapshot(p: String) -> Dictionary:
	if not FileAccess.file_exists(p):
		return {"exists": false}
	return {"exists": true, "text": FileAccess.get_file_as_string(p), "modified": FileAccess.get_modified_time(p)}


func _write_old_file(values: Dictionary, version := -1) -> void:
	var config := ConfigFile.new()
	if version >= 0:
		config.set_value(GameSettings.SECTION, GameSettings.VERSION_KEY, version)
	for key: String in values:
		config.set_value(GameSettings.SECTION, key, values[key])
	config.save(_path)


func test_an_old_saved_100_percent_loads_as_auto_and_fits_the_window() -> void:
	# What builds before version 2 wrote: every key, ui_scale at its old default.
	_write_old_file({"music_volume": 0.4, "ui_scale": 1.0, "fullscreen": false})
	var s := GameSettings.new()
	s.load_from(_path)
	assert_float(s.ui_scale).is_equal(0.0)
	assert_float(s.music_volume).is_equal_approx(0.4, 0.001)
	assert_str(s.scale_mode).is_equal(WindowFit.FIT)
	# So 1920x1080 draws at the fit scale, not 100%.
	assert_float(WindowFit.scale_for(Vector2(1920, 1080), s.ui_scale, s.scale_mode)) \
		.is_equal_approx(1080.0 / 820.0, 0.0001)
	# The migrated file is saved back with the current version.
	var config := ConfigFile.new()
	config.load(_path)
	assert_int(int(config.get_value(GameSettings.SECTION, GameSettings.VERSION_KEY, 0))) \
		.is_equal(GameSettings.current_version())
	assert_float(float(config.get_value(GameSettings.SECTION, "ui_scale"))).is_equal(0.0)


func test_another_old_size_was_a_choice_and_stays() -> void:
	_write_old_file({"ui_scale": 1.5}, 1)
	var s := GameSettings.new()
	s.load_from(_path)
	assert_float(s.ui_scale).is_equal(1.5)


func test_a_current_file_keeps_a_chosen_100_percent() -> void:
	var s := GameSettings.new()
	s.load_from(_path)
	s.set_value("ui_scale", 1.0)
	var again := GameSettings.new()
	again.load_from(_path)
	assert_float(again.ui_scale).is_equal(1.0)


func test_tests_and_tools_keep_the_shared_settings_in_memory() -> void:
	# The test runner's main loop is a script, as every -s tool's is.
	assert_str(GameSettings.shared_path()).is_empty()
	var shared := GameSettings.shared()
	assert_str(shared.path).is_empty()
	var before := shared.music_volume
	shared.set_value("music_volume", 0.123)
	assert_int(shared.save()).is_equal(ERR_FILE_BAD_PATH)
	shared.set_value("music_volume", before)
	# The settings screen saves through the shared settings too.
	var effects := shared.effects_volume
	var screen := SettingsScreen.open_overlay(self)
	screen.sliders["effects_volume"].value = 0.33
	screen.close()
	shared.set_value("effects_volume", effects)
	await get_tree().process_frame
	assert_dict(_snapshot(GameSettings.player_path())).is_equal(_player_before)


func test_an_environment_variable_points_tools_at_a_file() -> void:
	OS.set_environment(GameSettings.PATH_ENV, _path)
	assert_str(GameSettings.shared_path()).is_equal(_path)
	OS.unset_environment(GameSettings.PATH_ENV)
	assert_str(GameSettings.shared_path()).is_empty()
