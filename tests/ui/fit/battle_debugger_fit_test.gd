extends GdUnitTestSuite
## The battle debugger (S9b) beside a battle: the screen shrinks to the room
## the panel leaves and lays itself out there, as in a window that wide, so
## every unit card, the dock and the strip stay whole, in both views.

const DEMO := "res://ui/dev/battle_debugger/battle_debugger_demo.tscn"
const VIEWS: Array[Vector2] = [Vector2(1920, 1080), Vector2(1600, 900), Vector2(1280, 820)]


func after_test() -> void:
	ScreenFit.restore(get_tree().root)


func _open(view: Vector2) -> Node:
	ScreenFit.emulate(get_tree().root, view)
	var demo: Node = load(DEMO).instantiate()
	get_tree().root.add_child(demo)
	for i in 6:
		await get_tree().process_frame
	return demo


func _check_fits(demo: Node, view: Vector2, label: String) -> void:
	var screen: BattleScreen = demo.screen
	var dbg: BattleDebugger = demo.debugger
	var right := screen.get_global_rect().end.x
	var expected := view.x - mini(dbg.panel_width(), maxi(0, int(view.x) - 1280))
	assert_float(right).override_failure_message("%s: screen ends at %s" % [label, right]).is_equal_approx(expected, 1.0)
	for id: String in screen.unit_panels:
		var panel: Control = screen.unit_panels[id]
		assert_float(panel.get_global_rect().end.x).override_failure_message(
			"%s: %s's card ends at %s, past %s" % [label, id, panel.get_global_rect().end.x, right]).is_less_equal(right + 0.5)
	assert_float(screen.control_strip.get_global_rect().end.x).is_less_equal(right + 0.5)
	assert_float(screen.cancel_button.get_global_rect().end.x).is_less_equal(right + 0.5)
	assert_float(screen.prompt_label.size.x).override_failure_message(
		"%s: the status line is %s wide" % [label, screen.prompt_label.size.x]).is_greater(120.0)
	if view.x - dbg.panel_width() >= 1280:
		assert_float(dbg.get_global_rect().position.x).is_greater_equal(right - 0.5)


func test_every_view_fits_beside_the_panel() -> void:
	for view in VIEWS:
		var demo := await _open(view)
		for mode: StringName in [&"detailed", &"compact"]:
			demo.screen._on_strip_changed(&"view", mode)
			for i in 4:
				await get_tree().process_frame
			_check_fits(demo, view, "%dx%d %s" % [view.x, view.y, mode])
		demo.queue_free()
		await get_tree().process_frame


func test_hiding_the_panel_gives_the_screen_its_width_back() -> void:
	var demo := await _open(Vector2(1920, 1080))
	demo.debugger.visible = false
	for i in 4:
		await get_tree().process_frame
	assert_float(demo.screen.get_global_rect().end.x).is_equal_approx(1920.0, 1.0)
	demo.queue_free()
