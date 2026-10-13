extends GdUnitTestSuite
## The map on the design system (ui/README.md rules 7-16): the compact top
## bar, the map's control strip with lenses and "?", lens pins, the hover
## card, Region / Squad / Log tabs, the region card's flags and headlines,
## right-click detail, the early-only hint and the opaque news toast.

const SCENE := "res://ui/overworld/overworld.tscn"
const PLACEHOLDER := "res://data/regions/act1_placeholder.json"

var _runner: GdUnitSceneRunner


func before_test() -> void:
	_runner = scene_runner(SCENE)
	await _runner.simulate_frames(2)
	_screen().region_file = PLACEHOLDER
	assert_str(_screen().start_new_run()).is_empty()
	await _runner.simulate_frames(1)


func after_test() -> void:
	DetailModal.close_current()


func _screen() -> Node:
	return _runner.scene()


func _first(standing: Campaign.Standing) -> String:
	var screen := _screen()
	for r in screen.campaign.map.regions:
		if screen.campaign.standing(r.id) == standing:
			return r.id
	return ""


func test_the_countdown_leads_the_top_bar_and_carries_the_day_in_its_tooltip() -> void:
	var screen := _screen()
	assert_str(screen._countdown.text).is_equal("Payload in %d days" % screen.campaign.days_left())
	assert_bool(screen._day_line.visible).is_false()
	var tip := UiTooltip.spec(screen._countdown_box)
	assert_str(tip["numbers"]).contains("Day %d of" % screen.campaign.day())
	assert_str(tip["numbers"]).contains("Territories %d of %d" % [screen.campaign.state.owned.size(), screen.campaign.map.regions.size()])
	assert_int((tip["math"] as Array).size()).is_equal(1)
	# The grid is a compact meter; its rate is in the tooltip.
	assert_bool(screen._grid_rate.visible).is_false()
	assert_str(UiTooltip.spec(screen._grid_meter)["numbers"]).contains("a day")


func test_the_screen_has_one_map_strip_with_four_lenses() -> void:
	var screen := _screen()
	var strips: Array = screen.find_children("*", "ControlStrip", true, false)
	assert_int(strips.size()).is_equal(1)
	for lens in [&"defense", &"pressure", &"resources", &"odds"]:
		assert_object(screen.map_strip.button(&"lens", lens)).override_failure_message(str(lens)).is_not_null()
	assert_str(screen.map_view.lens).is_equal(str(UiIcons.kit("map.lens", "defense")))


func test_each_lens_pins_only_its_regions() -> void:
	var screen := _screen()
	screen.map_strip.press(&"lens", &"defense")
	await _runner.simulate_frames(2)
	for id: String in screen.map_view.pin_rects:
		assert_bool(screen.campaign.is_owned(id)).override_failure_message(id).is_false()
	screen.map_strip.press(&"lens", &"pressure")
	await _runner.simulate_frames(2)
	assert_str(screen.map_view.lens).is_equal("pressure")
	assert_bool(screen.map_view.pin_rects.is_empty()).is_false()
	for id: String in screen.map_view.pin_rects:
		assert_bool(screen.campaign.is_owned(id)).override_failure_message(id).is_true()


func test_pins_never_overlap() -> void:
	var screen := _screen()
	for lens in [&"defense", &"resources", &"odds"]:
		screen.map_strip.press(&"lens", lens)
		await _runner.simulate_frames(2)
		var rects: Array = screen.map_view.pin_rects.values()
		for i in rects.size():
			for j in range(i + 1, rects.size()):
				assert_bool((rects[i] as Rect2).intersects(rects[j])).override_failure_message(str(lens)).is_false()


func test_the_legend_hides_behind_the_question_mark() -> void:
	var screen := _screen()
	assert_bool(screen._legend.visible).is_false()
	screen.map_strip.press(&"legend")
	assert_bool(screen._legend.visible).is_true()
	screen.map_strip.press(&"legend")
	assert_bool(screen._legend.visible).is_false()


func test_hovering_a_region_shows_its_card() -> void:
	var screen := _screen()
	var id := _first(Campaign.Standing.IN_RANGE)
	screen.map_view.region_hovered.emit(id)
	assert_bool(screen._hover_card.visible).is_true()
	var strip: StatStrip = screen._hover_card.find_children("*", "StatStrip", true, false)[0]
	assert_array(strip.kinds()).is_equal(["ring", "pips", "chip"])
	screen.map_view.region_hovered.emit("")
	assert_bool(screen._hover_card.visible).is_false()


func test_a_right_click_on_a_region_opens_everything_about_it() -> void:
	var screen := _screen()
	var id := _first(Campaign.Standing.IN_RANGE)
	screen.map_view.region_detail_requested.emit(id)
	assert_bool(DetailModal.is_open()).is_true()
	assert_str(DetailModal.current.title).is_equal(screen.campaign.map.get_region(id).name)


func test_the_region_card_has_its_headlines_and_flags() -> void:
	var screen := _screen()
	var hostile := _first(Campaign.Standing.IN_RANGE)
	screen.map_view.select(hostile)
	await _runner.simulate_frames(1)
	var strip: StatStrip = screen._panel.find_child("Headlines", true, false)
	assert_array(strip.kinds()).is_equal(["ring", "pips", "chip"])
	assert_object(screen._panel.find_child("Flag_in_range", true, false)).is_not_null()
	assert_object(screen._panel.find_child("More", true, false)).is_not_null()
	var mine := _first(Campaign.Standing.OWNED)
	screen.campaign.state.pressure[mine] = screen.campaign.tuning.ring_warning_at
	screen.map_view.select(mine)
	await _runner.simulate_frames(1)
	strip = screen._panel.find_child("Headlines", true, false)
	assert_array(strip.kinds()).is_equal(["ring", "chip", "chip"])
	var warned: bool = screen._panel.find_child("Flag_under_attack", true, false) != null \
		or screen._panel.find_child("Flag_uprising", true, false) != null
	assert_bool(warned).is_true()


func test_a_fortified_region_carries_the_flag() -> void:
	var screen := _screen()
	var hostile := _first(Campaign.Standing.IN_RANGE)
	screen.campaign.state.escalation["fortify"][hostile] = 1
	var flags: Array = screen.region_flags(hostile)
	assert_bool(flags.any(func(f: Flag) -> bool: return f.name == "Flag_fortified")).is_true()
	for f: Node in flags:
		f.free()


func test_the_side_panel_has_region_squad_and_log_tabs() -> void:
	var screen := _screen()
	assert_array(screen.side_tabs.ids()).is_equal([&"region", &"squad", &"log"])
	screen.side_tabs.select(&"squad")
	await _runner.simulate_frames(1)
	assert_int(screen._squad.get_child_count()).is_equal(screen.campaign.squad_provider.get_squad().size())
	screen.side_tabs.select(&"region")
	screen.log_event("one")
	screen.log_event("two")
	assert_str(screen.side_tabs.button(&"log").text).starts_with("Log ")
	screen.side_tabs.select(&"log")
	assert_str(screen.side_tabs.button(&"log").text).is_equal("Log")


func test_the_first_turn_hint_shows_only_early() -> void:
	var screen := _screen()
	screen.map_view.select("")
	await _runner.simulate_frames(1)
	assert_bool(OverworldTestHelpers.panel_has_text(screen, "Pick a territory")).is_true()
	while screen.campaign.day() <= int(UiIcons.kit("map.hint_days", 2)):
		screen.campaign.wait()
	screen._refresh()
	assert_bool(OverworldTestHelpers.panel_has_text(screen, "Pick a territory")).is_false()


func test_the_news_toast_is_opaque() -> void:
	var screen := _screen()
	var card: Node = screen.escalation_hud.news
	var box := (card as Control).get_theme_stylebox("panel") as StyleBoxFlat
	assert_float(box.bg_color.a).is_equal(1.0)
