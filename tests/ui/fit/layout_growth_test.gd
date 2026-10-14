extends GdUnitTestSuite
## Big views are used: the map grows at its own shape, the side panel takes
## its share, the top bar compacts in steps instead of running off, and a
## battle falls back to compact cards while detailed ones do not fit.

const MapView := preload("res://ui/overworld/map_view.gd")


func after_test() -> void:
	ScreenFit.restore(get_tree().root)
	get_tree().paused = false


func test_the_map_frame_keeps_the_art_shape() -> void:
	var view: MapView = auto_free(MapView.new())
	var art := UiIcons.kit_vector("map.frame", Vector2(880, 580))
	view.size = Vector2(2000, 800)
	var f := view.frame()
	assert_float(f.size.x / f.size.y).is_equal_approx(art.x / art.y, 0.01)
	assert_float(f.size.y).is_equal(800.0)
	assert_float(f.get_center().x).is_equal_approx(1000.0, 1.0)
	# A point maps into the frame and back.
	var p := Vector2(0.25, 0.75)
	var back: Vector2 = view.view_to_map(view._point(p))
	assert_vector(back).is_equal_approx(p, Vector2(0.0001, 0.0001))


func test_the_map_grows_on_a_big_view() -> void:
	ScreenFit.emulate(get_tree().root, Vector2(1920, 1080))
	var map: Control = await ScreenFit.open("act1_map_early", self)
	var overworld: Control = map.overworld
	var share := float(UiIcons.kit("map.side_panel_share", 0.25))
	assert_float(overworld.map_view.size.x).is_greater(1300.0)
	assert_float(overworld.map_view.size.y).is_greater(700.0)
	assert_float(overworld._side.size.x).is_equal_approx(1920.0 * share, 2.0)
	# The escalation hud sits over the map wherever it is.
	assert_vector(overworld.escalation_hud.size).is_equal(overworld.map_view.size)
	map.queue_free()


func test_the_top_bar_compacts_instead_of_running_off() -> void:
	ScreenFit.emulate(get_tree().root, Vector2(1280, 820))
	var map: Control = await ScreenFit.open("run_map_crowded", self)
	assert_int(map.top_bar_level).is_greater(0)
	var rates: Array = map._income.find_children("Rate", "", true, false)
	for r: Control in rates:
		assert_bool(r.visible).is_false()
	assert_float(map._top_row.get_global_rect().end.x).is_less_equal(1280.0)
	# On a wide view everything shows again.
	ScreenFit.emulate(get_tree().root, Vector2(2560, 1440))
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(map.top_bar_level).is_equal(0)
	map.queue_free()


func test_icon_only_action_buttons_keep_their_name_on_hover() -> void:
	var b: ActionButton = auto_free(ActionButton.make("action_home", "Home"))
	b.set_icon_only(true)
	assert_bool(b.is_icon_only()).is_true()
	assert_str(str(UiTooltip.spec(b))).contains("Home")


func test_a_boss_fight_falls_back_to_compact_cards_on_a_short_view() -> void:
	ScreenFit.emulate(get_tree().root, Vector2(1280, 820))
	var flow: DemoRunFlow = await ScreenFit.open("act1_boss_detailed", self)
	var battle := flow.battle_screen
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(battle.compact).is_true()
	assert_bool(battle.control_strip.button(&"view", &"detailed").disabled).is_true()
	# A taller view brings the player's choice back.
	ScreenFit.emulate(get_tree().root, Vector2(2560, 1440))
	for i in 4:
		await get_tree().process_frame
	assert_bool(battle.compact).is_false()
	assert_bool(battle.control_strip.button(&"view", &"detailed").disabled).is_false()
	flow.queue_free()
