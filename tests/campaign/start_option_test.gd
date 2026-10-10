extends GdUnitTestSuite
## Starting locations, headless, on the shipped Seattle map. Each start holds
## different ground and brings different traits, and those change early play.

const SEATTLE := "res://data/regions/seattle.json"
const PLACEHOLDER := "res://data/regions/act1_placeholder.json"
const TUNING := "res://data/tuning/overworld.json"

var _map: RegionMap
var _tuning: MapTuning


func before_test() -> void:
	_map = RegionMap.load_file(SEATTLE)
	_tuning = MapTuning.load_file(TUNING)


func _campaign(start_id: String) -> Campaign:
	var start := _map.get_start(start_id)
	return Campaign.new(_map, _tuning, StubSquadProvider.new(), StubFightService.new(),
		Campaign.new_run_state(_map, _tuning, start))


## Waits until a held region's pressure forces a defense; returns the time.
func _points_to_first_forced_defense(c: Campaign) -> int:
	while c.pending_defense().is_empty() and not c.is_over():
		c.wait()
	return c.state.time_points


func test_seattle_has_three_starts_with_the_stated_traits() -> void:
	var options := _map.start_options()
	assert_int(options.size()).is_equal(3)
	var north := _map.get_start("north_end")
	assert_array(Array(north.regions)).contains_exactly(["northgate", "lake_city"])
	assert_float(north.pressure_rate_factor).is_equal(1.0)
	var steel := _map.get_start("duwamish_steelworks")
	assert_array(Array(steel.regions)).contains_exactly(["west_seattle"])
	assert_int(steel.income_bonus[MapRegion.POWER]).is_equal(3)
	assert_float(steel.material).is_equal(10.0)
	var beacon := _map.get_start("beacon_substation")
	assert_array(Array(beacon.regions)).contains_exactly(["beacon_hill"])
	assert_float(beacon.pressure_rate_factor).is_equal(0.5)
	assert_object(_map.get_start("")).is_same(north)
	assert_object(_map.get_start("nowhere")).is_null()


func test_the_default_start_matches_starts_owned() -> void:
	assert_array(Array(_map.get_start("").regions)).contains_exactly(Array(_map.starting_ids()))


func test_a_map_without_starts_offers_its_starts_owned_regions() -> void:
	var map := RegionMap.load_file(PLACEHOLDER)
	var options := map.start_options()
	assert_int(options.size()).is_equal(1)
	assert_array(Array(options[0].regions)).contains_exactly(["aurora_data_center", "substation_9"])
	assert_str(options[0].id).is_empty()


func test_each_start_begins_holding_its_own_regions() -> void:
	assert_array(Array(_campaign("north_end").state.owned)).contains_exactly(["northgate", "lake_city"])
	assert_array(Array(_campaign("duwamish_steelworks").state.owned)).contains_exactly(["west_seattle"])
	assert_array(Array(_campaign("beacon_substation").state.owned)).contains_exactly(["beacon_hill"])
	assert_str(_campaign("beacon_substation").state.start_id).is_equal("beacon_substation")


func test_two_starts_change_early_play() -> void:
	var north := _campaign("north_end")
	var beacon := _campaign("beacon_substation")
	# North End holds two territories and earns more energy from day one.
	assert_int(north.income_per_day()[MapRegion.ENERGY]).is_equal(4)
	assert_int(beacon.income_per_day()[MapRegion.ENERGY]).is_equal(0)
	assert_int(beacon.income_per_day()[MapRegion.POWER]).is_equal(4)
	# Beacon Hill's locals slow pressure: its first forced defense comes later.
	# North End: (0.6 + 0.6 x 1) x 1.5 = 1.8 a point, full at point 56.
	# Beacon Hill: (0.6 + 0.6 x 2) x 1.5 x 0.5 = 1.35 a point, full at point 75.
	assert_float(north.pressure_rate("northgate")).is_equal_approx(1.8, 1e-9)
	assert_float(beacon.pressure_rate("beacon_hill")).is_equal_approx(1.35, 1e-9)
	assert_int(_points_to_first_forced_defense(north)).is_equal(56)
	assert_int(_points_to_first_forced_defense(beacon)).is_equal(75)


func test_extra_grid_power_recovers_the_grid_faster() -> void:
	var north := _campaign("north_end")
	var steel := _campaign("duwamish_steelworks")
	north.state.grid = 50.0
	steel.state.grid = 50.0
	for i in 4:
		north.wait()
		steel.wait()
	# Grid power a point is power income / regen divisor 4: North End 1, the
	# Steelworks 0 + 3 bonus.
	assert_float(north.state.grid).is_equal_approx(51.0, 1e-9)
	assert_float(steel.state.grid).is_equal_approx(53.0, 1e-9)
	assert_float(steel.state.material).is_greater(north.state.material)


func test_the_start_pressure_factor_survives_a_save() -> void:
	var beacon := _campaign("beacon_substation")
	var resumed := Campaign.new(_map, _tuning, StubSquadProvider.new(), StubFightService.new(),
		beacon.state.duplicate_state())
	assert_float(resumed.pressure_rate("beacon_hill")).is_equal(beacon.pressure_rate("beacon_hill"))
	assert_int(resumed.income_per_day()[MapRegion.POWER]).is_equal(beacon.income_per_day()[MapRegion.POWER])


func test_a_start_naming_an_unknown_region_is_rejected() -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SEATTLE))
	d["starts"][0]["regions"] = ["northgate", "atlantis"]
	assert_array(RegionMap.from_dict(d).errors).contains(["start 'north_end' lists unknown region 'atlantis'"])


func test_bad_start_traits_are_rejected() -> void:
	var errors: Array[String] = []
	var start := StartOption.from_dict({"id": "x", "name": "X", "description": "D", "regions": ["a"],
		"income_bonus": {"power": -1}, "pressure_rate_factor": "low"}, errors)
	assert_object(start).is_null()
	assert_array(errors).contains([
		"start 'x' income_bonus.power must be a whole number 0 or more",
		"start 'x' pressure_rate_factor must be a number"])
