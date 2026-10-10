extends GdUnitTestSuite
## The overworld's presentation, headless, on the act 1 placeholder map:
## hover, captures and number popups shown once the map is in view, the
## animated grid bar, the faction row and the act music.

const SCENE := "res://ui/overworld/overworld.tscn"
const PLACEHOLDER := "res://data/regions/act1_placeholder.json"
const TARGET := "refinery_row"

var _runner: GdUnitSceneRunner


func before_test() -> void:
	_runner = scene_runner(SCENE)
	await _runner.simulate_frames(2)
	_screen().region_file = PLACEHOLDER
	assert_str(_screen().start_new_run()).is_empty()
	await _runner.simulate_frames(1)


func _screen() -> Node:
	return _runner.scene()


func test_the_screen_uses_the_pixel_theme() -> void:
	assert_object(_screen().theme).is_same(ScreenTheme.theme())
	assert_object(_screen().theme.default_font.base_font).is_equal(PixelTheme.font())


func test_hovering_a_region_lights_it() -> void:
	var view: Control = _screen().map_view
	view._hover_at(view.label_position(TARGET))
	assert_str(view.fx.hovered_id).is_equal(TARGET)
	assert_int(view.mouse_default_cursor_shape).is_equal(Control.CURSOR_POINTING_HAND)
	await _runner.simulate_frames(20, 20)
	assert_float(view.fx.hover_amount(TARGET)).is_equal(1.0)
	view._hover_at(null)
	assert_str(view.fx.hovered_id).is_empty()


func test_a_capture_out_of_sight_plays_when_the_map_shows_again() -> void:
	var screen := _screen()
	screen.visible = false
	assert_bool(await screen.campaign.attack(TARGET)).is_true()
	await _runner.simulate_frames(2)
	assert_bool(screen.campaign.is_owned(TARGET)).is_true()
	# Held while the map is hidden behind the fight.
	assert_array(Array(screen.unshown_changes().captured)).contains_exactly([TARGET])
	assert_bool(screen.map_view.fx.is_capturing(TARGET)).is_false()
	# It still looks hostile until its capture plays.
	assert_bool(screen.map_view.fx.is_held(TARGET)).is_true()
	screen.visible = true
	await _runner.simulate_frames(1)
	assert_object(screen.unshown_changes()).is_null()
	assert_bool(screen.map_view.fx.is_capturing(TARGET)).is_true()
	await _runner.simulate_frames(60, 20)
	assert_bool(screen.map_view.fx.is_capturing(TARGET)).is_false()


func test_a_capture_waits_for_the_message_to_close() -> void:
	var screen := _screen()
	screen._on_attack(TARGET)
	await _runner.simulate_frames(3)
	assert_bool(screen._modal.visible).is_true()
	assert_bool(screen.can_show_changes()).is_false()
	assert_bool(screen.map_view.fx.is_capturing(TARGET)).is_false()
	_button(screen._modal_buttons, "CONTINUE").pressed.emit()
	await _runner.simulate_frames(1)
	assert_bool(screen.map_view.fx.is_capturing(TARGET)).is_true()


func test_the_grid_bar_slides_down_with_a_trailing_ghost() -> void:
	var screen := _screen()
	var before: float = screen._grid_bar.fill_ratio
	await screen.campaign.attack(TARGET)
	await _shown(screen)
	var after: float = screen.campaign.state.grid / screen.campaign.tuning.max_grid
	assert_float(after).is_less(before)
	assert_float(screen._grid_bar.fill_ratio).is_equal_approx(after, 1e-6)
	assert_float(screen._grid_bar.trail_ratio).is_greater(after)
	await _runner.simulate_frames(60, 20)
	assert_float(screen._grid_bar.trail_ratio).is_equal_approx(after, 1e-6)


func test_gains_and_losses_pop_as_numbers() -> void:
	var screen := _screen()
	await screen.campaign.attack(TARGET)
	await _shown(screen)
	var texts: Array = screen._popups.get_children().map(func(p: NumberPopup) -> String: return p.text)
	# The stub fight pays energy and material (plus the days' income) and
	# drains the grid: sign, number and word together.
	for pattern: String in ["^\\+\\d+ EN$", "^\\+\\d+ MAT$", "^-\\d+% GRID$"]:
		var regex := RegEx.create_from_string(pattern)
		assert_bool(texts.any(func(t: String) -> bool: return regex.search(t) != null)) \
			.override_failure_message("%s in %s" % [pattern, texts]).is_true()


func test_a_new_run_shows_no_changes() -> void:
	var screen := _screen()
	screen.start_new_run()
	await _runner.simulate_frames(1)
	assert_int(screen._popups.get_child_count()).is_equal(0)
	assert_object(screen.unshown_changes()).is_null()


func test_the_territory_panel_names_the_faction_when_the_data_has_one() -> void:
	var screen := _screen()
	screen.map_view.select(TARGET)
	await _runner.simulate_frames(1)
	assert_object(screen._panel.find_child("Faction", true, false)).is_null()
	var lookup := FactionLookup.new()
	lookup.read({"factions": {"rust": {"name": "Rustborn", "color": "#c86b3c"}}, "by_act": {"0": "rust"}})
	screen.factions = lookup
	screen.map_view.select("")
	screen.map_view.select(TARGET)
	await _runner.simulate_frames(1)
	var row: Node = screen._panel.find_child("Faction", true, false)
	assert_object(row).is_not_null()
	assert_array(_texts(row)).contains(["Rustborn"])


func test_the_shared_pool_shows_one_meter_and_no_energy_count() -> void:
	var screen := _screen()
	assert_str(screen._grid_title.text).is_equal("GRID CAPACITY")
	assert_object(screen._income_label("energy")).is_not_null()
	screen.campaign.variants.choose(CampaignVariants.ENERGY_GRID, CampaignVariants.ENERGY_SHARED_POOL)
	screen._refresh()
	assert_bool(screen.is_shared_pool()).is_true()
	assert_str(screen._grid_title.text).is_equal("POWER POOL")
	assert_object(screen._income_label("energy")).is_null()
	assert_object(screen._income_label("material")).is_not_null()
	# A pool change pops as a pool number.
	screen._pop_number("grid", 6)
	assert_str((screen._popups.get_child(-1) as NumberPopup).text).is_equal("+6% POOL")


func test_act_1_plays_its_music() -> void:
	assert_str(_screen().music.track).is_equal("act1_metro")


## Waits until the screen has shown the changes it held.
func _shown(screen: Node) -> void:
	var guard := 0
	while screen.unshown_changes() != null and guard < 10:
		await _runner.simulate_frames(1)
		guard += 1
	assert_object(screen.unshown_changes()).is_null()


func _button(container: Node, text: String) -> Button:
	for child in container.get_children():
		if child is Button and child.text == text:
			return child
	return null


func _texts(node: Node) -> Array:
	var out := []
	if node is Label:
		out.append(node.text)
	for child in node.get_children():
		out.append_array(_texts(child))
	return out
