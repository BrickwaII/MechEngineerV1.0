extends GdUnitTestSuite
## The overworld screen, headless. Input events do not arrive in headless mode,
## so these drive the screen through the same calls its input handlers make.
## These run on the act 1 placeholder map; overworld_acts_test.gd covers the
## shipped greater Seattle map, the start choice and the act zooms.

const SCENE := "res://ui/overworld/overworld.tscn"
const SAVE_PATH := "user://overworld_test.save"
const PLACEHOLDER := "res://data/regions/act1_placeholder.json"

var _runner: GdUnitSceneRunner


func before_test() -> void:
	_runner = scene_runner(SCENE)
	await _runner.simulate_frames(2)
	_screen().region_file = PLACEHOLDER
	assert_str(_screen().start_new_run()).is_empty()
	await _runner.simulate_frames(1)


func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func _screen() -> Node:
	return _runner.scene()


func test_a_region_file_override_replaces_the_act1_map() -> void:
	var screen := _screen()
	assert_object(screen.campaign).is_not_null()
	assert_str(screen.campaign.map.id).is_equal("act1_placeholder")
	assert_int(screen.campaign.map.regions.size()).is_equal(12)
	assert_str(screen.map_view.selected_id).is_empty()
	# A map with one start offers no choice.
	screen.show_start_choice()
	assert_bool(screen._modal.visible).is_false()


func test_every_region_is_hit_at_its_own_label() -> void:
	var view: Control = _screen().map_view
	for region: MapRegion in _screen().campaign.map.regions:
		assert_str(view.region_at(view.label_position(region.id))).is_equal(region.id)


func test_a_point_inside_a_polygon_selects_that_region() -> void:
	var view: Control = _screen().map_view
	# Hydro Dam spans roughly x 0.03-0.26, y 0.32-0.68 of the map.
	assert_str(view.region_at(Vector2(0.15, 0.5) * view.size)).is_equal("hydro_dam")
	assert_str(view.region_at(Vector2(-5, -5))).is_empty()


func test_selecting_a_region_fills_the_panel() -> void:
	var screen := _screen()
	screen.map_view.select("hydro_dam")
	await _runner.simulate_frames(1)
	var texts := _panel_texts(screen)
	assert_array(texts).contains(["Hydro Dam", "DEFENSE", "YOUR ODDS", "ATTACK"])
	screen.map_view.select("substation_9")
	await _runner.simulate_frames(1)
	texts = _panel_texts(screen)
	assert_array(texts).contains(["Substation 9", "PRESSURE", "REINFORCE", "Attack building from Downtown Exchange"])


func test_out_of_reach_attack_button_is_disabled() -> void:
	var screen := _screen()
	screen.map_view.select("military_depot")
	await _runner.simulate_frames(1)
	var button := _button(screen._panel, "ATTACK")
	assert_bool(button.disabled).is_true()
	screen.map_view.select("refinery_row")
	await _runner.simulate_frames(1)
	assert_bool(_button(screen._panel, "ATTACK").disabled).is_false()


func test_a_pending_attack_shows_a_ghost_and_committing_it_advances_time() -> void:
	var screen := _screen()
	screen.map_view.select("hydro_dam")
	await _runner.simulate_frames(1)
	assert_float(screen._time_bar.ghost_ratio).is_equal_approx(3.0 / 48.0, 1e-6)
	assert_float(screen._grid_bar.ghost_ratio).is_equal_approx(0.10, 1e-6)
	_button(screen._panel, "ATTACK").pressed.emit()
	# ATTACK opens the pre-fight step first; FIGHT starts the fight.
	assert_bool(screen._modal.visible).is_true()
	assert_str(screen._modal_title.text).is_equal("Hydro Dam")
	assert_int(screen.campaign.state.time_points).is_equal(0)
	(screen._modal_buttons.get_child(0) as Button).pressed.emit()
	await _runner.simulate_frames(3)
	assert_int(screen.campaign.state.time_points).is_equal(3)
	assert_bool(screen.campaign.is_owned("hydro_dam")).is_true()
	assert_bool(screen._modal.visible).is_true()
	assert_str(screen._modal_title.text).is_equal("Captured Hydro Dam")


func test_a_full_ring_opens_the_forced_defense() -> void:
	var screen := _screen()
	screen.campaign.state.pressure["substation_9"] = 99.0
	screen._on_wait()
	await _runner.simulate_frames(1)
	assert_bool(screen._modal.visible).is_true()
	assert_str(screen._modal_title.text).is_equal("Substation 9 is under attack")
	var defend := screen._modal_buttons.get_child(0) as ActionButton
	assert_str(defend.label_text).is_equal("Defend")
	defend.pressed.emit()
	await _runner.simulate_frames(3)
	# The stub loses at Downtown Exchange's defense of 4.
	assert_str(screen._modal_title.text).is_equal("Lost Substation 9")
	assert_bool(screen.campaign.is_owned("substation_9")).is_false()


func test_save_and_load_restore_the_run() -> void:
	var screen := _screen()
	screen.campaign.wait()
	screen.campaign.reinforce("aurora_data_center")
	var saved: Dictionary = screen.campaign.state.to_dict()
	assert_int(screen.save_run(SAVE_PATH)).is_equal(OK)
	screen.start_new_run()
	assert_int(screen.campaign.state.time_points).is_equal(0)
	assert_bool(screen.load_run(SAVE_PATH)).is_true()
	assert_dict(screen.campaign.state.to_dict()).is_equal(saved)


static func _panel_texts(screen: Node) -> Array:
	var texts := []
	for node in screen._panel.find_children("*", "", true, false):
		if node is Label or node is Button:
			texts.append(node.text)
	return texts


static func _button(root: Node, text: String) -> Button:
	for node in root.find_children("*", "Button", true, false):
		if node.text == text:
			return node
	return null


func test_losses_resources_and_actions_show_as_icons_with_tooltips() -> void:
	var screen := _screen()
	await _runner.simulate_frames(1)
	assert_str(screen._losses.value_text()).is_equal("3")
	assert_str(str(UiTooltip.spec(screen._losses).body)).contains("Lost battles left")
	var energy: IconStat = screen._income_label("energy").get_child(0)
	assert_str(str(UiTooltip.spec(energy).body)).contains("Reinforce")
	assert_str(str(UiTooltip.spec(energy).body)).contains("Retreat")
	assert_bool(screen._repair_button.visible).is_true()
	assert_str(screen._repair_button.cost_icon_id).is_equal("material")
	assert_bool(screen._ff_button.visible).is_false()
	screen.show_pre_fight("hydro_dam")
	var labels: Array = screen._modal_buttons.get_children().map(func(b: ActionButton) -> String: return b.label_text)
	assert_array(labels).is_equal(["Fight", "Breach", "Retreat"])
	assert_str((screen._modal_buttons.get_child(2) as ActionButton).cost_icon_id).is_equal("energy")
