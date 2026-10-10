extends GdUnitTestSuite

const ACT1 := "res://data/regions/act1_placeholder.json"
const TUNING := "res://data/tuning/overworld.json"
const SAVE_PATH := "user://run_state_test.save"


func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func _campaign(state: RunState = null) -> Campaign:
	return Campaign.new(RegionMap.load_file(ACT1), MapTuning.load_file(TUNING),
		StubSquadProvider.new(), StubFightService.new(), state)


## Plays a fixed mix of actions, so pressure, grid and stock hold fractions.
func _play(c: Campaign) -> void:
	await c.attack("hydro_dam")
	c.wait()
	c.reinforce("substation_9")
	await c.attack("downtown_exchange")
	c.wait()


func test_a_mid_run_save_reloads_identically() -> void:
	var c := _campaign()
	await _play(c)
	assert_int(c.state.time_points).is_equal(9)
	assert_int(c.state.save_file(SAVE_PATH)).is_equal(OK)
	var loaded := RunState.load_file(SAVE_PATH)
	assert_object(loaded).is_not_null()
	assert_dict(loaded.to_dict()).is_equal(c.state.to_dict())
	assert_float(loaded.grid).is_equal(c.state.grid)
	assert_float(loaded.pressure["hydro_dam"]).is_equal(c.state.pressure["hydro_dam"])


func test_a_reloaded_run_plays_on_exactly_like_the_original() -> void:
	var original := _campaign()
	await _play(original)
	original.state.save_file(SAVE_PATH)
	var resumed := _campaign(RunState.load_file(SAVE_PATH))
	await _play(original)
	await _play(resumed)
	assert_dict(resumed.state.to_dict()).is_equal(original.state.to_dict())


func test_a_pending_defense_survives_a_reload() -> void:
	var c := _campaign()
	c.state.pressure["substation_9"] = 100.0
	c.state.save_file(SAVE_PATH)
	var resumed := _campaign(RunState.load_file(SAVE_PATH))
	assert_str(resumed.pending_defense()).is_equal("substation_9")


func test_a_broken_save_loads_as_null() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_var({"version": 1, "owned": []})
	file.close()
	assert_object(RunState.load_file(SAVE_PATH)).is_null()


func test_a_file_that_is_not_a_save_loads_as_null() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string("not a save")
	file.close()
	assert_object(RunState.load_file(SAVE_PATH)).is_null()


func test_a_version_1_save_loads_as_act_1_with_the_default_start() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_var({"version": 1, "region_set_id": "act1_placeholder", "owned": ["substation_9"],
		"pressure": {"substation_9": 12.5}, "energy": 3.0, "material": 4.0, "time_points": 7, "grid": 80.0})
	file.close()
	var loaded := RunState.load_file(SAVE_PATH)
	assert_object(loaded).is_not_null()
	assert_int(loaded.act).is_equal(0)
	assert_str(loaded.start_id).is_empty()
	assert_float(loaded.pressure["substation_9"]).is_equal(12.5)
	assert_dict(loaded.income_bonus).is_empty()


func test_the_act_and_start_traits_round_trip() -> void:
	var state := RunState.new()
	state.region_set_id = "north_america_33"
	state.act = 1
	state.start_id = "redmond_substation"
	state.owned = PackedStringArray(["washington"])
	state.pressure["washington"] = 1.0 / 3.0
	state.income_bonus[MapRegion.POWER] = 3
	state.pressure_rate_factor["washington"] = 0.5
	assert_int(state.save_file(SAVE_PATH)).is_equal(OK)
	assert_dict(RunState.load_file(SAVE_PATH).to_dict()).is_equal(state.to_dict())


func test_a_save_from_before_variants_loads_with_every_default() -> void:
	var d := _campaign().state.to_dict()
	for key in ["variants", "expansion", "focus_id"]:
		d.erase(key)
	var loaded := RunState.from_dict(d)
	assert_object(loaded).is_not_null()
	assert_dict(loaded.variants).is_empty()
	assert_dict(loaded.expansion).is_empty()
	assert_str(loaded.focus_id).is_empty()
	var c := _campaign(loaded)
	assert_dict(c.variants.non_default()).is_empty()


func test_a_new_run_keeps_its_variant_choices() -> void:
	var c := _campaign()
	assert_dict(c.state.variants).is_equal(CampaignVariants.defaults().run_choices())
