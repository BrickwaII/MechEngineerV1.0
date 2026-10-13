extends GdUnitTestSuite
## The Esc menu on its own: RESUME, SETTINGS, MAIN MENU, and the confirm step.


func after_test() -> void:
	var overlay := get_tree().root.get_node_or_null("SettingsOverlay")
	if overlay != null:
		get_tree().root.remove_child(overlay)
		overlay.free()


func _menu(confirm := false) -> PauseMenu:
	var menu := PauseMenu.new()
	if confirm:
		menu.confirm_title = "Leave the battle?"
		menu.confirm_body = "The fight is called off."
	var runner := scene_runner(auto_free(menu))
	await runner.simulate_frames(1)
	return menu


func _escape() -> InputEventKey:
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.physical_keycode = KEY_ESCAPE
	key.pressed = true
	return key


func test_the_menu_has_resume_settings_and_main_menu_as_icon_buttons() -> void:
	var menu := await _menu()
	assert_str(menu.resume_button.label_text).is_equal("Resume")
	assert_str(menu.resume_button.action_icon_id).is_equal("action_resume")
	assert_str(menu.settings_button.label_text).is_equal("Settings")
	assert_str(menu.settings_button.action_icon_id).is_equal("action_settings")
	assert_str(menu.home_button.label_text).is_equal("Main menu")
	assert_str(menu.home_button.action_icon_id).is_equal("action_home")
	assert_int(menu.process_mode).is_equal(Node.PROCESS_MODE_ALWAYS)
	assert_bool(menu.menu_box.visible).is_true()
	assert_bool(menu.is_confirming()).is_false()


func test_resume_and_esc_resume() -> void:
	var menu := await _menu()
	var resumed := [0]
	menu.resumed.connect(func() -> void: resumed[0] += 1)
	menu.resume_button.pressed.emit()
	assert_int(resumed[0]).is_equal(1)
	menu._unhandled_input(_escape())
	assert_int(resumed[0]).is_equal(2)


func test_main_menu_leaves_at_once_with_nothing_to_confirm() -> void:
	var menu := await _menu()
	var left := [0]
	menu.home_requested.connect(func() -> void: left[0] += 1)
	menu.home_button.pressed.emit()
	assert_int(left[0]).is_equal(1)
	assert_bool(menu.is_confirming()).is_false()


func test_main_menu_asks_first_when_leaving_costs_something() -> void:
	var menu := await _menu(true)
	var left := [0]
	var resumed := [0]
	menu.home_requested.connect(func() -> void: left[0] += 1)
	menu.resumed.connect(func() -> void: resumed[0] += 1)
	menu.home_button.pressed.emit()
	assert_int(left[0]).is_equal(0)
	assert_bool(menu.is_confirming()).is_true()
	assert_bool(menu.menu_box.visible).is_false()
	assert_str(menu.confirm_body_label.text).is_equal("The fight is called off.")
	# Esc while asking goes back to the menu, not out of it.
	menu._unhandled_input(_escape())
	assert_bool(menu.is_confirming()).is_false()
	assert_int(resumed[0]).is_equal(0)
	# STAY goes back too; LEAVE leaves.
	menu.home_button.pressed.emit()
	menu.stay_button.pressed.emit()
	assert_bool(menu.is_confirming()).is_false()
	menu.home_button.pressed.emit()
	menu.leave_button.pressed.emit()
	assert_int(left[0]).is_equal(1)


func test_settings_opens_the_settings_screen_over_everything() -> void:
	var menu := await _menu()
	menu.settings_button.pressed.emit()
	assert_bool(SettingsScreen.is_open(get_tree().root)).is_true()
