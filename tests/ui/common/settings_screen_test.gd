extends GdUnitTestSuite
## The settings screen changes, saves and closes.

var settings: GameSettings
var _path := ""


func before_test() -> void:
	_path = "user://test_settings_screen_%d.cfg" % Time.get_ticks_usec()
	settings = GameSettings.new()
	settings.load_from(_path)


func after_test() -> void:
	DirAccess.remove_absolute(_path)


func _screen() -> SettingsScreen:
	var screen: SettingsScreen = load(SettingsScreen.SCENE_PATH).instantiate()
	screen.settings = settings
	add_child(screen)
	return auto_free(screen)


func test_it_shows_the_current_settings() -> void:
	settings.music_volume = 0.35
	settings.reduced_motion = true
	var screen := _screen()
	assert_float(screen.sliders["music_volume"].value).is_equal_approx(0.35, 0.001)
	assert_bool(screen.reduced_toggle.button_pressed).is_true()
	assert_bool(screen.sliders["shake_strength"].editable).is_false()


func test_moving_a_control_changes_and_saves_the_setting() -> void:
	var screen := _screen()
	screen.sliders["effects_volume"].value = 0.4
	screen.shake_toggle.button_pressed = false
	screen.speed_option.select(3)
	screen.speed_option.item_selected.emit(3)
	assert_float(settings.effects_volume).is_equal_approx(0.4, 0.001)
	assert_bool(settings.shake_enabled).is_false()
	assert_str(settings.animation_speed).is_equal("skip")
	var reloaded := GameSettings.new()
	reloaded.load_from(_path)
	assert_float(reloaded.effects_volume).is_equal_approx(0.4, 0.001)
	assert_str(reloaded.animation_speed).is_equal("skip")


func test_defaults_button_restores_the_data_defaults() -> void:
	settings.set_value("music_volume", 0.1)
	var screen := _screen()
	screen.reset_button.pressed.emit()
	assert_float(settings.music_volume).is_equal_approx(FeelData.settings()["defaults"]["music_volume"], 0.001)
	assert_float(screen.sliders["music_volume"].value).is_equal_approx(settings.music_volume, 0.001)


func test_the_overlay_opens_once_and_closes() -> void:
	var host: Node = auto_free(Node.new())
	add_child(host)
	var screen := SettingsScreen.open_overlay(host, settings)
	assert_object(SettingsScreen.open_overlay(host, settings)).is_same(screen)
	assert_bool(SettingsScreen.is_open(host)).is_true()
	screen.close_button.pressed.emit()
	await await_idle_frame()
	assert_bool(SettingsScreen.is_open(host)).is_false()


func test_other_screens_can_open_it_with_a_hotkey_action() -> void:
	var action: String = FeelData.settings()["open_action"]
	assert_bool(InputMap.has_action(action)).is_true()
	assert_bool(InputMap.action_get_events(action).is_empty()).is_false()
