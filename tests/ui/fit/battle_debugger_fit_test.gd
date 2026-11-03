extends GdUnitTestSuite
## The battle debugger (S9b) beside a battle: the screen shrinks to the room
## the panel leaves and lays itself out there, as in a window that wide, so
## every unit card, the dock and the strip stay whole, in both views.

const DEMO := "res://ui/dev/battle_debugger/battle_debugger_demo.tscn"
const VIEWS: Array[Vector2] = [Vector2(1920, 1080), Vector2(1600, 900), Vector2(1280, 820)]


## The root window's size before a test resized it (Vector2i.ZERO: not resized).
var _window_size := Vector2i.ZERO


func after_test() -> void:
	# Put the window back as it was, so later suites see the root unchanged.
	if _window_size != Vector2i.ZERO:
		get_tree().root.size = _window_size
		_window_size = Vector2i.ZERO
	ScreenFit.restore(get_tree().root)


func _open(view: Vector2) -> Node:
	ScreenFit.emulate(get_tree().root, view)
	var demo: Node = load(DEMO).instantiate()
	get_tree().root.add_child(demo)
	for i in 6:
		await get_tree().process_frame
	return demo


## The screen keeps the whole of `width` (as with no panel); the panel sits
## right of it, no wider than its width; every card, the strip, Cancel and
## the status line are whole inside the screen.
func _check_fits(demo: Node, width: float, label: String) -> void:
	var screen: BattleScreen = demo.screen
	var dbg: BattleDebugger = demo.debugger
	var right := screen.get_global_rect().end.x
	assert_float(right).override_failure_message("%s: screen ends at %s, not %s" % [label, right, width]).is_equal_approx(width, 1.0)
	for id: String in screen.unit_panels:
		var panel: Control = screen.unit_panels[id]
		assert_float(panel.get_global_rect().end.x).override_failure_message(
			"%s: %s's card ends at %s, past %s" % [label, id, panel.get_global_rect().end.x, right]).is_less_equal(right + 0.5)
	assert_float(screen.control_strip.get_global_rect().end.x).is_less_equal(right + 0.5)
	assert_float(screen.cancel_button.get_global_rect().end.x).is_less_equal(right + 0.5)
	assert_float(screen.prompt_label.size.x).override_failure_message(
		"%s: the status line is %s wide" % [label, screen.prompt_label.size.x]).is_greater(120.0)
	var panel_rect := dbg.get_global_rect()
	assert_float(panel_rect.position.x).override_failure_message(
		"%s: the panel starts at %s, inside the screen" % [label, panel_rect.position.x]).is_greater_equal(right - 0.5)
	assert_float(panel_rect.size.x).override_failure_message(
		"%s: the panel is %s wide" % [label, panel_rect.size.x]).is_less_equal(dbg.panel_width() + 0.5)
	assert_float(panel_rect.end.x).is_less_equal(dbg.get_viewport().get_visible_rect().size.x + 0.5)


func test_every_view_fits_beside_the_panel() -> void:
	for view in VIEWS:
		var demo := await _open(view)
		for mode: StringName in [&"detailed", &"compact"]:
			demo.screen._on_strip_changed(&"view", mode)
			for i in 4:
				await get_tree().process_frame
			_check_fits(demo, view.x, "%dx%d %s" % [view.x, view.y, mode])
		demo.queue_free()
		await get_tree().process_frame


func test_hiding_the_panel_gives_the_screen_its_width_back() -> void:
	var demo := await _open(Vector2(1920, 1080))
	demo.debugger.visible = false
	for i in 4:
		await get_tree().process_frame
	assert_float(demo.screen.get_global_rect().end.x).is_equal_approx(1920.0, 1.0)
	assert_float(get_tree().root.get_visible_rect().size.x).is_equal_approx(1920.0, 1.0)
	demo.queue_free()


## A real window, fitted by WindowFit (1920x1080 draws a 1456x820 view):
## the screen keeps that view's width and the panel gets room beside it.
func test_a_fitted_1920_window_keeps_the_screen_whole() -> void:
	var root := get_tree().root
	_window_size = root.size
	root.size = Vector2i(1920, 1080)
	if root.size != Vector2i(1920, 1080):
		return  # this display cannot size the window
	WindowFit.held = false
	WindowFit.apply(root, 0.0, WindowFit.FIT)
	var width := root.get_visible_rect().size.x
	var demo: Node = load(DEMO).instantiate()
	root.add_child(demo)
	for i in 6:
		await get_tree().process_frame
	_check_fits(demo, width, "fitted 1920x1080")
	demo.debugger.visible = false
	await get_tree().process_frame
	assert_float(root.get_visible_rect().size.x).is_equal_approx(width, 1.0)
	demo.queue_free()
