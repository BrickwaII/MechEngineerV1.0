extends GdUnitTestSuite
## The act plan and the zoom from act 1 to act 2, headless, on the shipped
## data/tuning/acts.json, Seattle and Puget Sound maps.

const ACTS := "res://data/tuning/acts.json"
const SAVE_PATH := "user://act_plan_test.save"


func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func _plan() -> ActPlan:
	var plan := ActPlan.load_file(ACTS)
	assert_array(plan.errors).is_empty()
	return plan


func _campaign(plan: ActPlan, act: int, state: RunState = null) -> Campaign:
	return Campaign.new(plan.load_map(act), plan.load_tuning(act),
		StubSquadProvider.new(), StubFightService.new(), state)


func _plan_dict() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(ACTS))


func test_shipped_acts_are_seattle_then_puget_sound() -> void:
	var plan := _plan()
	assert_int(plan.act_count()).is_equal(2)
	assert_str(plan.act_name(0)).is_equal("Seattle")
	assert_str(plan.act_name(1)).is_equal("Puget Sound")
	assert_bool(plan.has_next(0)).is_true()
	assert_bool(plan.has_next(1)).is_false()
	for act in plan.act_count():
		var map := plan.load_map(act)
		assert_array(map.errors).is_empty()
		assert_array(plan.load_tuning(act).errors).is_empty()
	assert_str(plan.load_map(0).id).is_equal("seattle")
	var act2 := plan.load_map(1)
	assert_str(act2.id).is_equal("puget_sound")
	assert_bool(act2.has_region(plan.acts[1]["zoom_focus"])).is_true()
	assert_int(act2.regions.size()).is_greater_equal(plan.load_map(0).regions.size() - 3)


func test_shipped_zoom_numbers() -> void:
	var plan := _plan()
	assert_float(plan.energy_kept).is_equal(1.0)
	assert_float(plan.material_kept).is_equal(1.0)
	assert_float(plan.grid_restore).is_equal(25.0)
	assert_int(plan.held_per_bonus_region).is_equal(5)
	assert_int(plan.max_bonus_regions).is_equal(2)
	assert_bool(plan.keep_income_bonus).is_true()


func test_bonus_regions_grow_with_regions_held_up_to_the_cap() -> void:
	var plan := _plan()
	assert_int(plan.bonus_region_count(1)).is_equal(0)
	assert_int(plan.bonus_region_count(4)).is_equal(0)
	assert_int(plan.bonus_region_count(5)).is_equal(1)
	assert_int(plan.bonus_region_count(10)).is_equal(2)
	assert_int(plan.bonus_region_count(15)).is_equal(2)


func test_bonus_regions_are_the_focus_neighbors_with_the_lowest_defense() -> void:
	var plan := _plan()
	var act2 := plan.load_map(1)
	# Seattle's neighbors: Everett 3, Kitsap 4, Eastside 4, Kent Valley 2.
	assert_array(Array(plan.zoom_regions(1, act2, 2))).contains_exactly(["seattle"])
	assert_array(Array(plan.zoom_regions(1, act2, 6))).contains_exactly(["seattle", "kent_valley"])
	assert_array(Array(plan.zoom_regions(1, act2, 12))).contains_exactly(["everett", "seattle", "kent_valley"])


func test_the_zoom_carries_resources_grid_and_the_start_bonus() -> void:
	var plan := _plan()
	var act1 := _campaign(plan, 0, Campaign.new_run_state(plan.load_map(0), plan.load_tuning(0),
		plan.load_map(0).get_start("duwamish_steelworks")))
	act1.state.energy = 33.5
	act1.state.material = 21.25
	act1.state.grid = 60.0
	act1.state.time_points = 400
	act1.state.owned = PackedStringArray(["west_seattle", "sodo", "beacon_hill", "downtown", "rainier_valley"])
	var act2_map := plan.load_map(1)
	var act2_tuning := plan.load_tuning(1)
	var s := plan.zoom_state(act1.state, act2_map, act2_tuning)
	assert_int(s.act).is_equal(1)
	assert_str(s.region_set_id).is_equal("puget_sound")
	assert_str(s.start_id).is_equal("duwamish_steelworks")
	assert_array(Array(s.owned)).contains_exactly(["seattle", "kent_valley"])
	assert_float(s.pressure["seattle"]).is_equal(act2_tuning.start_pressure)
	assert_float(s.energy).is_equal(33.5)
	assert_float(s.material).is_equal(21.25)
	assert_float(s.grid).is_equal(85.0)
	assert_int(s.time_points).is_equal(0)
	assert_int(s.income_bonus[MapRegion.POWER]).is_equal(3)
	assert_dict(s.pressure_rate_factor).is_empty()


func test_the_grid_restore_stops_at_full() -> void:
	var plan := _plan()
	var from := Campaign.new_run_state(plan.load_map(0), plan.load_tuning(0))
	from.grid = 90.0
	assert_float(plan.zoom_state(from, plan.load_map(1), plan.load_tuning(1)).grid).is_equal(100.0)


func test_a_run_plays_act1_to_the_payload_then_act2_on_the_carried_state() -> void:
	var plan := _plan()
	var act1 := _campaign(plan, 0)
	assert_bool(await act1.attack("university_district")).is_true()
	while not act1.is_over():
		if not act1.pending_defense().is_empty():
			await act1.defend()
		else:
			act1.wait()
	assert_bool(act1.is_payload_due()).is_true()
	var energy := act1.state.energy
	var act2 := _campaign(plan, 1, plan.zoom_state(act1.state, plan.load_map(1), plan.load_tuning(1)))
	assert_bool(act2.is_payload_due()).is_false()
	assert_bool(act2.is_owned("seattle")).is_true()
	assert_float(act2.state.energy).is_equal(energy)
	assert_int(act2.standing("kent_valley")).is_equal(Campaign.Standing.IN_RANGE)
	assert_bool(await act2.attack("kent_valley")).is_true()
	assert_bool(act2.is_owned("kent_valley")).is_true()
	assert_int(act2.state.time_points).is_equal(act2.tuning.attack_time)


func test_an_act2_save_round_trips_with_its_act() -> void:
	var plan := _plan()
	var act1 := _campaign(plan, 0)
	act1.state.time_points = act1.tuning.total_points
	var act2 := _campaign(plan, 1, plan.zoom_state(act1.state, plan.load_map(1), plan.load_tuning(1)))
	await act2.attack("kent_valley")
	act2.wait()
	assert_int(act2.state.save_file(SAVE_PATH)).is_equal(OK)
	var loaded := RunState.load_file(SAVE_PATH)
	assert_int(loaded.act).is_equal(1)
	assert_dict(loaded.to_dict()).is_equal(act2.state.to_dict())
	var resumed := _campaign(plan, loaded.act, loaded)
	act2.wait()
	resumed.wait()
	assert_dict(resumed.state.to_dict()).is_equal(act2.state.to_dict())


func test_a_missing_zoom_key_is_an_error() -> void:
	var d := _plan_dict()
	(d["zoom"] as Dictionary).erase("grid_restore")
	assert_array(ActPlan.from_dict(d).errors).contains(["acts is missing 'zoom.grid_restore'"])


func test_a_later_act_needs_a_zoom_focus() -> void:
	var d := _plan_dict()
	(d["acts"][1] as Dictionary).erase("zoom_focus")
	assert_array(ActPlan.from_dict(d).errors).contains(["act 2 needs a 'zoom_focus' region id"])
