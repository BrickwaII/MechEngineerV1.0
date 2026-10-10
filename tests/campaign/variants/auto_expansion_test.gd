extends GdUnitTestSuite
## auto-expansion: held ground spreading into weak neighbors once a day.
##
## The test map is a row a - b - c, plus d next to a: a is held, b and c are
## weak (defense 1), d is strong (defense 4).

const TUNING := "res://data/tuning/overworld.json"


func _map() -> RegionMap:
	var regions := []
	var specs := {"a": [["b", "d"], 1, true], "b": [["a", "c"], 1, false], "c": [["b"], 1, false], "d": [["a"], 4, false]}
	var x := 0.0
	for id: String in specs:
		regions.append({"id": id, "name": id.to_upper(), "kind": "T",
			"polygon": [[x, 0], [x + 0.2, 0], [x + 0.2, 1]], "adjacent": specs[id][0],
			"provides": {"power": 0, "energy": 0, "material": 0}, "defense": specs[id][1],
			"pressure_base": 1, "starts_owned": specs[id][2]})
		x += 0.25
	var map := RegionMap.from_dict({"id": "row", "name": "Row", "regions": regions})
	assert_array(map.errors).is_empty()
	return map


func _variants(option := "simple", from_act := 1) -> CampaignVariants:
	var v := CampaignVariants.defaults()
	v.choose(CampaignVariants.AUTO_EXPANSION, option)
	(v.params_by_option[CampaignVariants.AUTO_EXPANSION]["simple"] as Dictionary)["from_act"] = from_act
	return v


func _campaign(v: CampaignVariants, act := 0) -> Campaign:
	var map := _map()
	var tuning := MapTuning.load_file(TUNING)
	var state := Campaign.new_run_state(map, tuning, null, v)
	state.act = act
	var c := Campaign.new(map, tuning, StubSquadProvider.new(), StubFightService.new(), state)
	# The test edits params, which a saved run would not keep; hand them over.
	c.variants = v
	return c


## Waits whole days, keeping pressure off so no forced defense stops the clock.
func _wait_days(c: Campaign, days: int) -> void:
	for i in days * c.tuning.points_per_day:
		for region_id in c.state.owned:
			c.state.pressure[region_id] = 0.0
		assert_bool(c.wait()).is_true()


func test_off_never_spreads() -> void:
	var c := _campaign(_variants("off"))
	_wait_days(c, 60)
	assert_array(Array(c.state.owned)).contains_exactly(["a"])
	assert_dict(c.state.expansion).is_empty()


func test_it_waits_for_its_act() -> void:
	var v := _variants("simple", 2)
	assert_bool(AutoExpansion.is_on(v, 0)).is_false()
	assert_bool(AutoExpansion.is_on(v, 1)).is_true()
	var c := _campaign(v, 0)
	_wait_days(c, 60)
	assert_array(Array(c.state.owned)).contains_exactly(["a"])


func test_only_weak_neighbors_of_held_ground_are_candidates() -> void:
	var c := _campaign(_variants())
	assert_array(Array(AutoExpansion.candidates(c.map, c.state, c.variants))).contains_exactly(["b"])


func test_progress_builds_once_a_day_and_claims_at_full() -> void:
	var v := _variants()
	var per_day := v.param_float(CampaignVariants.AUTO_EXPANSION, "progress_per_day")
	var c := _campaign(v)
	c.wait()
	assert_dict(c.state.expansion).is_empty()
	_wait_days(c, 1)
	assert_float(c.state.expansion["b"]).is_equal_approx(per_day, 0.0001)
	var claimed: Array[String] = []
	c.expanded.connect(func(id: String) -> void: claimed.append(id))
	_wait_days(c, ceili(AutoExpansion.FULL / per_day))
	assert_array(claimed).contains_exactly(["b"])
	assert_bool(c.is_owned("b")).is_true()
	assert_float(c.pressure_of("b")).is_less_equal(c.tuning.pressure_after_capture + 10.0)
	assert_bool(c.state.expansion.has("b")).is_false()


func test_the_focus_speeds_it_up() -> void:
	var v := _variants()
	var plain := _campaign(v)
	var focused := _campaign(v)
	focused.set_focus("c")
	_wait_days(plain, 2)
	_wait_days(focused, 2)
	var focus_multiplier := v.param_float(CampaignVariants.AUTO_EXPANSION, "focus_multiplier")
	assert_float(focused.state.expansion["b"]).is_equal_approx(plain.state.expansion["b"] * focus_multiplier, 0.0001)


func test_attacking_makes_a_region_the_focus() -> void:
	var c := _campaign(_variants())
	await c.attack("d")
	assert_str(c.state.focus_id).is_equal("d")


func test_progress_and_focus_survive_a_save_and_play_on_the_same() -> void:
	var v := _variants()
	var c := _campaign(v)
	c.set_focus("b")
	_wait_days(c, 3)
	var resumed := Campaign.new(c.map, MapTuning.load_file(TUNING), StubSquadProvider.new(), StubFightService.new(),
		RunState.from_dict(c.state.to_dict()))
	resumed.variants = v
	_wait_days(c, 20)
	_wait_days(resumed, 20)
	assert_dict(resumed.state.to_dict()).is_equal(c.state.to_dict())
