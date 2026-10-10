extends GdUnitTestSuite
## The act plan and the zooms from act 1 to act 2 to act 3, headless, on the
## shipped data/tuning/acts.json and each act's default map variant: the 12
## areas around Lake Washington, North America in 33 regions, the world in 20.

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


func test_shipped_acts_are_seattle_then_north_america_then_the_world() -> void:
	var plan := _plan()
	assert_int(plan.act_count()).is_equal(3)
	assert_str(plan.act_name(0)).is_equal("Greater Seattle")
	assert_str(plan.act_name(1)).is_equal("North America")
	assert_str(plan.act_name(2)).is_equal("The World")
	assert_bool(plan.has_next(0)).is_true()
	assert_bool(plan.has_next(1)).is_true()
	assert_bool(plan.has_next(2)).is_false()
	for act in plan.act_count():
		var map := plan.load_map(act)
		assert_array(map.errors).is_empty()
		assert_array(plan.load_tuning(act).errors).is_empty()
	assert_str(plan.load_map(0).id).is_equal("lake_washington_12")
	assert_str(plan.load_map(1).id).is_equal("north_america_33")
	assert_str(plan.load_map(2).id).is_equal("world_20")
	assert_str(plan.acts[1]["zoom_focus"]).is_equal("washington")
	assert_str(plan.acts[2]["zoom_focus"]).is_equal("united_states")
	for act in [1, 2]:
		assert_bool(plan.load_map(act).has_region(plan.acts[act]["zoom_focus"])).is_true()


func test_each_act_has_its_own_pacing() -> void:
	var plan := _plan()
	var days := []
	var references := []
	for act in plan.act_count():
		var t := plan.load_tuning(act)
		days.append(t.total_points / t.points_per_day)
		references.append(t.pressure_reference_regions)
		# On its default map an act builds pressure at the tuned scale.
		assert_float(_campaign(plan, act).pressure_scale()).is_equal(t.pressure_scale)
	assert_array(days).is_equal([100, 100, 100])
	assert_array(references).is_equal([12, 33, 20])
	assert_str(plan.load_tuning(1).node_style).is_equal(MapTuning.NODE_COMPACT)


func test_a_bigger_variant_builds_pressure_more_slowly_on_each_region() -> void:
	var plan := _plan()
	assert_bool(plan.choose_variant(0, "lake_washington_22")).is_true()
	var big := _campaign(plan, 0)
	assert_float(big.pressure_scale()).is_equal_approx(12.0 / 22.0, 1e-9)
	assert_bool(plan.choose_variant(0, "lake_washington_8")).is_true()
	assert_float(_campaign(plan, 0).pressure_scale()).is_equal_approx(12.0 / 8.0, 1e-9)


func test_each_act_offers_variants_and_plays_the_chosen_one() -> void:
	var plan := _plan()
	var ids := []
	for act in plan.act_count():
		ids.append(plan.variants(act).map(func(v: Dictionary) -> String: return v["id"]))
	assert_array(ids).is_equal([
		["lake_washington_8", "lake_washington_12", "lake_washington_16", "lake_washington_22"],
		["north_america_19", "north_america_33", "north_america_57"],
		["world_8", "world_20", "world_39"]])
	assert_str(plan.chosen_variant(1)).is_equal("north_america_33")
	assert_bool(plan.choose_variant(1, "north_america_19")).is_true()
	assert_str(plan.load_map(1).id).is_equal("north_america_19")
	assert_str(plan.acts[1]["zoom_focus"]).is_equal("pacific_northwest")
	assert_bool(plan.choose_variant(1, "atlantis")).is_false()
	assert_str(plan.chosen_variant(1)).is_equal("north_america_19")
	assert_bool(plan.choose_variant(1, "")).is_true()
	assert_str(plan.chosen_variant(1)).is_equal("north_america_33")
	assert_bool(plan.choose_variant(5, "")).is_false()


func test_a_default_variant_must_be_listed() -> void:
	var d := _plan_dict()
	d["acts"][0]["default_variant"] = "nowhere"
	assert_array(ActPlan.from_dict(d).errors).contains(["act 1's default_variant 'nowhere' is not one of its variants"])


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
	# Washington's neighbors: Oregon 1, the Northern Rockies 3, British Columbia 2.
	assert_array(Array(plan.zoom_regions(1, act2, 2))).contains_exactly(["washington"])
	assert_array(Array(plan.zoom_regions(1, act2, 6))).contains_exactly(["washington", "oregon"])
	assert_array(Array(plan.zoom_regions(1, act2, 12))).contains_exactly(["washington", "oregon", "british_columbia"])
	var act3 := plan.load_map(2)
	# The United States' neighbors: Canada 2, Mexico and the Caribbean 2, and
	# across the water Western Europe 5 and Siberia 3.
	assert_array(Array(plan.zoom_regions(2, act3, 6))).contains_exactly(["united_states", "canada"])
	assert_array(Array(plan.zoom_regions(2, act3, 12))).contains_exactly(["united_states", "canada", "mexico_caribbean"])


func test_the_zoom_carries_resources_grid_and_the_start_bonus() -> void:
	var plan := _plan()
	var act1 := _campaign(plan, 0, Campaign.new_run_state(plan.load_map(0), plan.load_tuning(0),
		plan.load_map(0).get_start("renton_works")))
	act1.state.energy = 33.5
	act1.state.material = 21.25
	act1.state.grid = 60.0
	act1.state.time_points = 400
	act1.state.owned = PackedStringArray(["north_seattle", "shoreline", "lake_forest_park", "bothell", "renton"])
	var act2_map := plan.load_map(1)
	var act2_tuning := plan.load_tuning(1)
	var s := plan.zoom_state(act1.state, act2_map, act2_tuning)
	assert_int(s.act).is_equal(1)
	assert_str(s.region_set_id).is_equal("north_america_33")
	assert_str(s.start_id).is_equal("renton_works")
	assert_array(Array(s.owned)).contains_exactly(["washington", "oregon"])
	assert_float(s.pressure["washington"]).is_equal(act2_tuning.start_pressure)
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
	assert_bool(await act1.attack("bothell")).is_true()
	while not act1.is_over():
		if not act1.pending_defense().is_empty():
			await act1.defend()
		else:
			act1.wait()
	assert_bool(act1.is_payload_due()).is_true()
	var energy := act1.state.energy
	var act2 := _campaign(plan, 1, plan.zoom_state(act1.state, plan.load_map(1), plan.load_tuning(1)))
	assert_bool(act2.is_payload_due()).is_false()
	assert_bool(act2.is_owned("washington")).is_true()
	assert_float(act2.state.energy).is_equal(energy)
	assert_int(act2.standing("oregon")).is_equal(Campaign.Standing.IN_RANGE)
	assert_bool(await act2.attack("oregon")).is_true()
	assert_bool(act2.is_owned("oregon")).is_true()
	assert_int(act2.state.time_points).is_equal(act2.tuning.attack_time)


func test_act2_zooms_out_to_the_world_on_the_carried_state() -> void:
	var plan := _plan()
	var act1 := _campaign(plan, 0)
	act1.state.time_points = act1.tuning.total_points
	var act2 := _campaign(plan, 1, plan.zoom_state(act1.state, plan.load_map(1), plan.load_tuning(1)))
	act2.state.energy = 70.0
	act2.state.material = 12.5
	act2.state.grid = 40.0
	act2.state.time_points = act2.tuning.total_points
	act2.state.owned = PackedStringArray(["washington", "oregon", "california", "great_basin", "arizona"])
	var s := plan.zoom_state(act2.state, plan.load_map(2), plan.load_tuning(2))
	assert_int(s.act).is_equal(2)
	assert_str(s.region_set_id).is_equal("world_20")
	assert_str(s.start_id).is_equal("north_end")
	assert_array(Array(s.owned)).contains_exactly(["united_states", "canada"])
	assert_float(s.energy).is_equal(70.0)
	assert_float(s.material).is_equal(12.5)
	assert_float(s.grid).is_equal(65.0)
	assert_int(s.time_points).is_equal(0)
	var act3 := _campaign(plan, 2, s)
	assert_bool(act3.map.is_globe()).is_true()
	assert_int(act3.standing("mexico_caribbean")).is_equal(Campaign.Standing.IN_RANGE)
	assert_bool(await act3.attack("mexico_caribbean")).is_true()
	assert_bool(act3.is_owned("mexico_caribbean")).is_true()


func test_an_act2_save_round_trips_with_its_act() -> void:
	var plan := _plan()
	var act1 := _campaign(plan, 0)
	act1.state.time_points = act1.tuning.total_points
	var act2 := _campaign(plan, 1, plan.zoom_state(act1.state, plan.load_map(1), plan.load_tuning(1)))
	await act2.attack("oregon")
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
	(d["acts"][1]["variants"][0] as Dictionary).erase("zoom_focus")
	assert_array(ActPlan.from_dict(d).errors).contains(["act 2 variant 'north_america_19' needs a 'zoom_focus' region id"])


func test_an_act3_save_round_trips_with_its_act() -> void:
	var plan := _plan()
	var state := Campaign.new_run_state(plan.load_map(0), plan.load_tuning(0))
	state.time_points = plan.load_tuning(0).total_points
	state = plan.zoom_state(state, plan.load_map(1), plan.load_tuning(1))
	state = plan.zoom_state(state, plan.load_map(2), plan.load_tuning(2))
	var act3 := _campaign(plan, 2, state)
	await act3.attack("mexico_caribbean")
	act3.wait()
	assert_int(act3.state.save_file(SAVE_PATH)).is_equal(OK)
	var loaded := RunState.load_file(SAVE_PATH)
	assert_int(loaded.act).is_equal(2)
	assert_str(loaded.region_set_id).is_equal("world_20")
	assert_dict(loaded.to_dict()).is_equal(act3.state.to_dict())
