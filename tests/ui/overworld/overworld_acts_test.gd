extends GdUnitTestSuite
## The overworld screen on the shipped acts, headless: Seattle as act 1, the
## choice of start, and the zoom out to Puget Sound after the act 1 payload.

const SCENE := "res://ui/overworld/overworld.tscn"
const SAVE_PATH := "user://overworld_acts_test.save"

var _runner: GdUnitSceneRunner


func before_test() -> void:
	_runner = scene_runner(SCENE)
	await _runner.simulate_frames(2)


func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func _screen() -> Node:
	return _runner.scene()


## Spends the rest of act 1's countdown and returns once the payload shows.
func _reach_payload(screen: Node) -> void:
	screen.campaign.state.time_points = screen.campaign.tuning.total_points - 1
	screen._on_wait()
	await _runner.simulate_frames(1)


func test_the_scene_opens_on_seattle_with_the_start_choice() -> void:
	var screen := _screen()
	assert_str(screen.campaign.map.id).is_equal("seattle")
	assert_int(screen.campaign.state.act).is_equal(0)
	assert_bool(screen._modal.visible).is_true()
	assert_str(screen._modal_title.text).is_equal("Choose a starting location")
	var texts := _texts(screen._modal_options)
	assert_array(texts).contains(["North End Uplink", "Duwamish Steelworks", "Beacon Hill Substation",
		"+3 grid power / day for the whole run", "Pressure builds 50% slower on its territories",
		"Holds 2 territories: Northgate, Lake City"])
	assert_int(_buttons(screen._modal_options, "START HERE").size()).is_equal(3)


func test_choosing_a_start_begins_the_run_there() -> void:
	var screen := _screen()
	_buttons(screen._modal_options, "START HERE")[1].pressed.emit()
	await _runner.simulate_frames(1)
	assert_bool(screen._modal.visible).is_false()
	assert_array(Array(screen.campaign.state.owned)).contains_exactly(["west_seattle"])
	assert_str(screen.campaign.state.start_id).is_equal("duwamish_steelworks")
	assert_str(screen._day_line.text).starts_with("ACT 1 · SEATTLE · DAY 1")


func test_the_act1_payload_offers_the_zoom() -> void:
	var screen := _screen()
	screen.choose_start("north_end")
	await _reach_payload(screen)
	assert_bool(screen._modal.visible).is_true()
	assert_str(screen._modal_eyebrow.text).is_equal("ACT 1 · PAYLOAD")
	assert_str(screen._modal_title.text).is_equal("The payload arrives")
	assert_object(_button(screen._modal_buttons, "ZOOM OUT")).is_not_null()


func test_zooming_out_loads_puget_sound_and_plays_the_transition() -> void:
	var screen := _screen()
	screen.choose_start("duwamish_steelworks")
	screen.campaign.state.energy = 42.0
	await _reach_payload(screen)
	_button(screen._modal_buttons, "ZOOM OUT").pressed.emit()
	await _runner.simulate_frames(2)
	assert_str(screen.campaign.map.id).is_equal("puget_sound")
	assert_int(screen.campaign.state.act).is_equal(1)
	assert_array(Array(screen.campaign.state.owned)).contains_exactly(["seattle"])
	assert_float(screen.campaign.state.energy).is_greater_equal(42.0)
	assert_int(screen.campaign.income_per_day()[MapRegion.POWER]).is_equal(3 + 3)
	assert_bool(screen.zooming).is_true()
	assert_float(screen.map_view.zoom).is_greater(1.0)
	assert_object(screen.map_view.inset_map).is_not_null()
	assert_str(screen.map_view.inset_map.id).is_equal("seattle")
	assert_bool(screen._modal.visible).is_false()
	await _runner.simulate_frames(80, 50)
	assert_bool(screen.zooming).is_false()
	assert_float(screen.map_view.zoom).is_equal(1.0)
	assert_object(screen.map_view.inset_map).is_null()
	assert_str(screen._day_line.text).starts_with("ACT 2 · PUGET SOUND · DAY 1")


func test_an_act2_run_saves_and_loads_into_act2() -> void:
	var screen := _screen()
	screen.choose_start("north_end")
	await _reach_payload(screen)
	assert_str(screen.advance_act()).is_empty()
	screen.campaign.wait()
	var saved: Dictionary = screen.campaign.state.to_dict()
	assert_int(screen.save_run(SAVE_PATH)).is_equal(OK)
	screen.start_new_run()
	assert_str(screen.campaign.map.id).is_equal("seattle")
	assert_bool(screen.load_run(SAVE_PATH)).is_true()
	assert_str(screen.campaign.map.id).is_equal("puget_sound")
	assert_dict(screen.campaign.state.to_dict()).is_equal(saved)


func test_the_last_act_payload_ends_the_run() -> void:
	var screen := _screen()
	screen.choose_start("north_end")
	await _reach_payload(screen)
	screen.advance_act()
	await _reach_payload(screen)
	assert_str(screen._modal_eyebrow.text).is_equal("RUN OVER")
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
