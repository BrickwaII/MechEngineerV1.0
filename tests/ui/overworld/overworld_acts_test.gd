extends GdUnitTestSuite
## The overworld screen on the shipped acts and their default map variants,
## headless: Lake Washington as act 1, the choice of start, the zoom out to
## North America after the act 1 payload, the zoom out to the globe after act
## 2, saves in every act, map variants, and the stub boss fight that ends the
## run.

const SCENE := "res://ui/overworld/overworld.tscn"
const SAVE_PATH := "user://overworld_acts_test.save"
const GlobeView := preload("res://ui/overworld/globe_view.gd")

var _runner: GdUnitSceneRunner


func before_test() -> void:
	_runner = scene_runner(SCENE)
	await _runner.simulate_frames(2)


func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func _screen() -> Node:
	return _runner.scene()


## Spends the rest of the act's countdown and returns once the payload shows.
func _reach_payload(screen: Node) -> void:
	screen.campaign.state.time_points = screen.campaign.tuning.total_points - 1
	screen._on_wait()
	await _runner.simulate_frames(1)


## Plays the zoom out from the payload modal to its end.
func _zoom_out(screen: Node) -> void:
	await _reach_payload(screen)
	_button(screen._modal_buttons, "ZOOM OUT").pressed.emit()
	await _runner.simulate_frames(2)
	await _runner.simulate_frames(80, 50)


func test_the_scene_opens_on_lake_washington_with_the_start_choice() -> void:
	var screen := _screen()
	assert_str(screen.campaign.map.id).is_equal("lake_washington_12")
	assert_int(screen.campaign.state.act).is_equal(0)
	assert_bool(screen._modal.visible).is_true()
	assert_str(screen._modal_title.text).is_equal("Choose a starting location")
	var texts := _texts(screen._modal_options)
	assert_array(texts).contains(["North End Uplink", "Renton Jet Works", "Redmond Substation",
		"+3 grid power / day for the whole run", "Pressure builds 50% slower on its territories",
		"Holds 2 territories: Shoreline, Lake Forest Park"])
	assert_int(_buttons(screen._modal_options, "START HERE").size()).is_equal(3)
	assert_bool(screen.map_view is GlobeView).is_false()


func test_choosing_a_start_begins_the_run_there() -> void:
	var screen := _screen()
	_buttons(screen._modal_options, "START HERE")[1].pressed.emit()
	await _runner.simulate_frames(1)
	assert_bool(screen._modal.visible).is_false()
	assert_array(Array(screen.campaign.state.owned)).contains_exactly(["renton"])
	assert_str(screen.campaign.state.start_id).is_equal("renton_works")
	assert_str(screen._day_line.text).starts_with("ACT 1 · GREATER SEATTLE · DAY 1")


func test_with_a_start_picker_there_is_no_choice() -> void:
	var screen := _screen()
	screen.start_picker = func(options: Array) -> String: return options[2].id
	screen.new_run()
	await _runner.simulate_frames(1)
	assert_bool(screen._modal.visible).is_false()
	assert_str(screen.campaign.state.start_id).is_equal("redmond_substation")


func test_the_act1_payload_offers_the_zoom() -> void:
	var screen := _screen()
	screen.choose_start("north_end")
	await _reach_payload(screen)
	assert_bool(screen._modal.visible).is_true()
	assert_str(screen._modal_eyebrow.text).is_equal("ACT 1 · PAYLOAD")
	assert_str(screen._modal_title.text).is_equal("The payload arrives")
	assert_object(_button(screen._modal_buttons, "ZOOM OUT")).is_not_null()


func test_zooming_out_loads_north_america_and_plays_the_transition() -> void:
	var screen := _screen()
	screen.choose_start("renton_works")
	screen.campaign.state.energy = 42.0
	await _reach_payload(screen)
	_button(screen._modal_buttons, "ZOOM OUT").pressed.emit()
	await _runner.simulate_frames(2)
	assert_str(screen.campaign.map.id).is_equal("north_america_33")
	assert_int(screen.campaign.state.act).is_equal(1)
	assert_array(Array(screen.campaign.state.owned)).contains_exactly(["washington"])
	assert_float(screen.campaign.state.energy).is_greater_equal(minf(42.0, screen.campaign.resource_cap(Stakes.ENERGY)))
	assert_int(screen.campaign.income_per_day()[MapRegion.POWER]).is_equal(1 + 3)
	assert_bool(screen.zooming).is_true()
	# The zoom starts with the Lake Washington map filling the view, in Washington.
	assert_float(screen.map_view.zoom).is_greater(20.0)
	assert_str(screen.campaign.map.region_at(screen.map_view.zoom_center)).is_equal("washington")
	assert_object(screen.map_view.inset_map).is_not_null()
	assert_str(screen.map_view.inset_map.id).is_equal("lake_washington_12")
	assert_bool(screen._modal.visible).is_false()
	# The act title card shows, the panels dim and the music changes.
	assert_bool(screen._act_title.visible).is_true()
	assert_str(screen.music.track).is_equal("act2_continent")
	await _runner.simulate_frames(80, 50)
	assert_bool(screen.zooming).is_false()
	assert_bool(screen._act_title.visible).is_false()
	for panel: Control in screen._hud:
		assert_float(panel.modulate.a).is_equal(1.0)
	assert_float(screen.map_view.zoom).is_equal(1.0)
	assert_object(screen.map_view.inset_map).is_null()
	assert_str(screen._day_line.text).starts_with("ACT 2 · NORTH AMERICA · DAY 1 / 100")


func test_the_zoom_keeps_the_old_map_in_place_as_it_shrinks() -> void:
	var screen := _screen()
	screen.choose_start("north_end")
	await _reach_payload(screen)
	screen.zoom_out()
	var view: Control = screen.map_view
	# At the start the old map fills the view.
	screen._set_zoom_progress(0.0)
	var start_center: Vector2 = view.zoom_center
	var start_width: float = 1.0 / view.zoom
	assert_vector(view._point(view.inset_rect.get_center())).is_equal_approx(view.size / 2.0, Vector2(1, 1))
	# The zoom turns about one map point, which stays put on screen.
	var k: Vector2 = (Vector2(0.5, 0.5) - start_center) / (start_width - 1.0)
	var fixed: Vector2 = start_center + k * start_width
	var fixed_on_screen: Vector2 = view._point(fixed)
	var widths := []
	for t in [0.0, 0.3, 0.7, 1.0]:
		screen._set_zoom_progress(t)
		widths.append(1.0 / view.zoom)
		assert_vector(view._point(fixed)).is_equal_approx(fixed_on_screen, Vector2(0.01, 0.01))
	assert_float(widths[0]).is_less(widths[1])
	assert_float(widths[1]).is_less(widths[2])
	assert_float(widths[3]).is_equal_approx(1.0, 1e-9)
	assert_vector(view.zoom_center).is_equal_approx(Vector2(0.5, 0.5), Vector2(1e-6, 1e-6))


func test_act2_zooms_out_to_the_globe() -> void:
	var screen := _screen()
	screen.choose_start("north_end")
	await _zoom_out(screen)
	assert_str(screen.campaign.map.id).is_equal("north_america_33")
	assert_bool(screen.map_view is GlobeView).is_false()
	screen.campaign.state.material = 17.0
	await _reach_payload(screen)
	assert_str(_button(screen._modal_buttons, "ZOOM OUT").text).is_equal("ZOOM OUT")
	_button(screen._modal_buttons, "ZOOM OUT").pressed.emit()
	await _runner.simulate_frames(2)
	assert_str(screen.campaign.map.id).is_equal("world_20")
	assert_int(screen.campaign.state.act).is_equal(2)
	assert_array(Array(screen.campaign.state.owned)).contains_exactly(["united_states"])
	assert_float(screen.campaign.state.material).is_greater_equal(17.0)
	assert_bool(screen.map_view is GlobeView).is_true()
	assert_object(screen.map_view.campaign).is_same(screen.campaign)
	assert_str(screen.map_view.inset_map.id).is_equal("north_america_33")
	assert_bool(screen.zooming).is_true()
	await _runner.simulate_frames(80, 50)
	assert_bool(screen.zooming).is_false()
	assert_str(screen._day_line.text).starts_with("ACT 3 · THE WORLD · DAY 1 / 100")
	assert_str(screen.music.track).is_equal("act3_globe")
	# The globe faces North America.
	assert_str(screen.map_view.region_at(screen.map_view.size / 2.0)).is_equal("united_states")


func test_an_act2_run_saves_and_loads_into_act2() -> void:
	var screen := _screen()
	screen.choose_start("north_end")
	await _reach_payload(screen)
	assert_str(screen.advance_act()).is_empty()
	screen.campaign.wait()
	var saved: Dictionary = screen.campaign.state.to_dict()
	assert_int(screen.save_run(SAVE_PATH)).is_equal(OK)
	screen.start_new_run()
	assert_str(screen.campaign.map.id).is_equal("lake_washington_12")
	assert_bool(screen.load_run(SAVE_PATH)).is_true()
	assert_str(screen.campaign.map.id).is_equal("north_america_33")
	assert_dict(screen.campaign.state.to_dict()).is_equal(saved)


func test_an_act3_run_saves_and_loads_onto_the_globe() -> void:
	var screen := _screen()
	screen.choose_start("north_end")
	await _reach_payload(screen)
	assert_str(screen.advance_act()).is_empty()
	await _reach_payload(screen)
	assert_str(screen.advance_act()).is_empty()
	await screen.campaign.attack("canada")
	var saved: Dictionary = screen.campaign.state.to_dict()
	assert_int(screen.save_run(SAVE_PATH)).is_equal(OK)
	screen.start_new_run()
	await _runner.simulate_frames(1)
	assert_bool(screen.map_view is GlobeView).is_false()
	assert_bool(screen.load_run(SAVE_PATH)).is_true()
	await _runner.simulate_frames(1)
	assert_str(screen.campaign.map.id).is_equal("world_20")
	assert_int(screen.campaign.state.act).is_equal(2)
	assert_dict(screen.campaign.state.to_dict()).is_equal(saved)
	assert_bool(screen.map_view is GlobeView).is_true()


func test_a_run_plays_the_chosen_map_variants() -> void:
	var screen := _screen()
	screen.act_variants = PackedStringArray(["lake_washington_8", "north_america_19", "world_8"])
	assert_str(screen.start_new_run("north_end")).is_empty()
	assert_str(screen.campaign.map.id).is_equal("lake_washington_8")
	await _reach_payload(screen)
	assert_str(screen.advance_act()).is_empty()
	assert_str(screen.campaign.map.id).is_equal("north_america_19")
	assert_array(Array(screen.campaign.state.owned)).contains_exactly(["pacific_northwest"])
	await _reach_payload(screen)
	assert_str(screen.advance_act()).is_empty()
	assert_str(screen.campaign.map.id).is_equal("world_8")
	assert_array(Array(screen.campaign.state.owned)).contains_exactly(["north_america"])
	screen.act_variants = PackedStringArray(["atlantis"])
	assert_str(screen.start_new_run()).contains("no map variant 'atlantis'")


func test_a_save_loads_on_the_variant_it_was_made_on() -> void:
	var screen := _screen()
	screen.act_variants = PackedStringArray(["", "north_america_57"])
	screen.start_new_run("north_end")
	await _reach_payload(screen)
	assert_str(screen.advance_act()).is_empty()
	assert_str(screen.campaign.map.id).is_equal("north_america_57")
	assert_int(screen.save_run(SAVE_PATH)).is_equal(OK)
	# A run on the defaults loads the save back onto its own variant.
	screen.act_variants = PackedStringArray()
	screen.start_new_run()
	assert_bool(screen.load_run(SAVE_PATH)).is_true()
	assert_str(screen.campaign.map.id).is_equal("north_america_57")


func test_the_last_act_payload_brings_the_boss_and_ends_the_run() -> void:
	var screen := _screen()
	screen.choose_start("north_end")
	await _reach_payload(screen)
	screen.advance_act()
	await _reach_payload(screen)
	screen.advance_act()
	await _reach_payload(screen)
	assert_str(screen._modal_eyebrow.text).is_equal("ACT 3 · FINAL PAYLOAD")
	assert_str(screen._modal_title.text).is_equal("The boss arrives")
	_button(screen._modal_buttons, "FIGHT THE BOSS").pressed.emit()
	await _runner.simulate_frames(3)
	# StubFightService loses at the boss's level 5.
	assert_str(screen._modal_eyebrow.text).is_equal("RUN OVER")
	assert_str(screen._modal_title.text).is_equal("The boss holds")
	assert_object(_button(screen._modal_buttons, "NEW RUN")).is_not_null()


static func _texts(root: Node) -> Array:
	var texts := []
	for node in root.find_children("*", "", true, false):
		if node is Label or node is Button:
			texts.append(node.text)
	return texts


static func _buttons(root: Node, text: String) -> Array:
	return root.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.text == text)


static func _button(root: Node, text: String) -> Button:
	var found := _buttons(root, text)
	return found[0] if not found.is_empty() else null
