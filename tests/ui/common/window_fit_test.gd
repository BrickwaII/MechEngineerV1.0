extends GdUnitTestSuite
## WindowFit: the view fills any window, grows on big screens in crisp steps,
## never drops below the minimum layout, and the fullscreen setting saves.

var _path := ""


func before_test() -> void:
	_path = "user://test_window_fit_%d.cfg" % Time.get_ticks_usec()


func after_test() -> void:
	DirAccess.remove_absolute(_path)


func test_the_minimum_comes_from_data() -> void:
	var v: Array = FeelData.settings()["display"]["min_size"]
	assert_vector(WindowFit.min_size()).is_equal(Vector2(v[0], v[1]))


func test_auto_picks_the_largest_step_that_fits() -> void:
	assert_float(WindowFit.scale_for(Vector2(1280, 820))).is_equal(1.0)
	assert_float(WindowFit.scale_for(Vector2(1920, 1080))).is_equal(1.0)
	assert_float(WindowFit.scale_for(Vector2(2560, 1440))).is_equal(1.5)
	assert_float(WindowFit.scale_for(Vector2(3440, 1440))).is_equal(1.5)
	assert_float(WindowFit.scale_for(Vector2(3840, 2160))).is_equal(2.5)


func test_big_windows_get_a_bigger_view_not_black_bars() -> void:
	assert_vector(WindowFit.view_size(Vector2(1920, 1080))).is_equal(Vector2(1920, 1080))
	var wide := WindowFit.view_size(Vector2(3440, 1440))
	assert_float(wide.x).is_equal_approx(3440.0 / 1.5, 0.01)
	assert_float(wide.y).is_equal(960.0)


func test_a_fixed_size_is_capped_to_what_fits() -> void:
	assert_float(WindowFit.scale_for(Vector2(1280, 820), 2.0)).is_equal(1.0)
	assert_float(WindowFit.scale_for(Vector2(2560, 1640), 2.0)).is_equal(2.0)
	assert_float(WindowFit.scale_for(Vector2(2560, 1440), 2.0)).is_equal(1.5)
	assert_bool(WindowFit.fits(Vector2(2560, 1440), 2.0)).is_false()
	assert_bool(WindowFit.fits(Vector2(2560, 1440), 1.5)).is_true()
	assert_bool(WindowFit.fits(Vector2(1280, 820), 0.0)).is_true()


func test_every_view_is_at_least_the_minimum() -> void:
	var least := WindowFit.min_size()
	for window: Vector2 in [Vector2(1280, 820), Vector2(1366, 768), Vector2(1600, 900),
			Vector2(1920, 1080), Vector2(2560, 1440), Vector2(3440, 1440), Vector2(1024, 600)]:
		for size: float in FeelData.settings()["ui_scale_options"]:
			var view := WindowFit.view_size(window, size)
			assert_bool(view.x >= least.x - 0.01 and view.y >= least.y - 0.01) \
				.override_failure_message("%s at %s gives %s" % [window, size, view]).is_true()


func test_small_screens_shrink_to_fit() -> void:
	var view := WindowFit.view_size(Vector2(1366, 768))
	assert_float(view.y).is_equal_approx(820.0, 0.01)
	assert_bool(WindowFit.scale_for(Vector2(1366, 768)) < 1.0).is_true()


func test_apply_sets_the_root_to_fill_its_window() -> void:
	var root := get_tree().root
	var before := [root.content_scale_factor, root.content_scale_size, root.content_scale_stretch]
	WindowFit.apply(root, 0.0)
	assert_int(root.content_scale_mode).is_equal(Window.CONTENT_SCALE_MODE_CANVAS_ITEMS)
	assert_int(root.content_scale_aspect).is_equal(Window.CONTENT_SCALE_ASPECT_EXPAND)
	assert_vector(Vector2(root.content_scale_size)).is_equal(Vector2(root.size))
	assert_float(root.content_scale_factor).is_equal(WindowFit.scale_for(Vector2(root.size)))
	root.content_scale_factor = before[0]
	root.content_scale_size = before[1]
	root.content_scale_stretch = before[2]


func test_fullscreen_is_saved_with_the_other_settings() -> void:
	var s := GameSettings.new()
	assert_bool(s.fullscreen).is_equal(FeelData.settings()["defaults"]["fullscreen"])
	s.load_from(_path)
	s.set_value("fullscreen", true)
	var again := GameSettings.new()
	again.load_from(_path)
	assert_bool(again.fullscreen).is_true()


func test_f11_and_alt_enter_toggle_fullscreen() -> void:
	var action: String = FeelData.settings()["fullscreen_action"]
	assert_bool(InputMap.has_action(action)).is_true()
	var f11 := InputEventKey.new()
	f11.physical_keycode = KEY_F11
	f11.pressed = true
	assert_bool(f11.is_action_pressed(action, false, true)).is_true()
	var alt_enter := InputEventKey.new()
	alt_enter.physical_keycode = KEY_ENTER
	alt_enter.alt_pressed = true
	alt_enter.pressed = true
	assert_bool(alt_enter.is_action_pressed(action, false, true)).is_true()
	var enter := InputEventKey.new()
	enter.physical_keycode = KEY_ENTER
	enter.pressed = true
	assert_bool(enter.is_action_pressed(action, false, true)).is_false()


func test_the_settings_screen_has_fullscreen_and_auto_size() -> void:
	var s := GameSettings.new()
	s.load_from(_path)
	var screen: SettingsScreen = auto_free(load(SettingsScreen.SCENE_PATH).instantiate())
	screen.settings = s
	add_child(screen)
	screen.fullscreen_toggle.button_pressed = true
	assert_bool(s.fullscreen).is_true()
	screen.fullscreen_toggle.button_pressed = false
	assert_str(screen.scale_option.get_item_text(0)).starts_with("Auto")
