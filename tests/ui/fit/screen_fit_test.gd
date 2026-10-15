extends GdUnitTestSuite
## Every play screen fits every supported view (ScreenFit): at each view the
## window sizes 1280x820 to 3440x1440 give at each interface size, no
## visible Control leaves the view or a clipping parent, no text is cut off,
## and no items of a top bar or strip overlap. Headless: the root is laid out
## at each view's size (ScreenFit.emulate); ui/demo/check_fit.gd does the same
## in a real window under xvfb, with pictures.

const MENUS: Array[String] = ["menu", "how_to_play", "settings", "whats_new", "load", "demo_picker", "draft"]
const AFTER: Array[String] = ["esc_menu", "end_panel", "act3_run_over",
	"readout_summary", "readout_growth", "readout_details"]


func after_test() -> void:
	ScreenFit.restore(get_tree().root)
	get_tree().paused = false


func _assert_fits(ids: Array[String]) -> void:
	var found: Dictionary = await ScreenFit.run(self, ids, ScreenFit.view_sizes())
	var lines: Array[String] = []
	for id: String in found:
		for line: String in found[id]:
			lines.append("%s: %s" % [id, line])
	assert_array(lines).override_failure_message("\n".join(lines.slice(0, 30))).is_empty()


func test_the_views_cover_every_window_and_interface_size() -> void:
	var views := ScreenFit.view_sizes()
	assert_bool(Vector2(1280, 820) in views).is_true()
	assert_bool(Vector2(3440, 1440) in views).is_true()
	for view in views:
		assert_bool(view.x >= WindowFit.min_size().x and view.y >= WindowFit.min_size().y).is_true()
	# Every screen the checker knows opens.
	assert_int(ScreenFit.screen_ids().size()).is_greater(30)


func test_the_menus_fit() -> void:
	await _assert_fits(MENUS)


func test_every_map_fits() -> void:
	var ids: Array[String] = ["run_map_crowded"]
	ids.append_array(ScreenFit.MAP_SCENARIOS)
	await _assert_fits(ids)


func test_every_fight_fits_in_both_views_with_a_card_focused() -> void:
	var ids: Array[String] = []
	for id in ScreenFit.screen_ids():
		if id.ends_with("_detailed") or id.ends_with("_compact"):
			ids.append(id)
	await _assert_fits(ids)


func test_the_esc_menu_end_panels_and_readout_fit() -> void:
	await _assert_fits(AFTER)


func test_the_checker_catches_what_does_not_fit() -> void:
	var host: Control = auto_free(Control.new())
	host.size = Vector2(200, 100)
	add_child(host)
	var row := HBoxContainer.new()
	row.position = Vector2(180, 0)
	host.add_child(row)
	var label := Label.new()
	label.text = "A label far too long for its place"
	label.clip_text = true
	label.custom_minimum_size.x = 40
	row.add_child(label)
	for i in 3:
		await get_tree().process_frame
	var problems := ScreenFit.problems(host, Rect2(0, 0, 200, 100))
	assert_bool(problems.any(func(p: String) -> bool: return p.contains("is outside"))).is_true()
	assert_bool(problems.any(func(p: String) -> bool: return p.contains("cut off"))).is_true()
