extends GdUnitTestSuite
## The overworld simulation, headless, on the shipped act 1 placeholder map and
## tuning. At the start the player holds Aurora Data Center (pressure base 1)
## and Substation 9 (pressure base 2), both on the border.

const ACT1 := "res://data/regions/act1_placeholder.json"
const TUNING := "res://data/tuning/overworld.json"


class AlwaysWins:
	extends FightService
	var requests: Array[FightRequest] = []

	func start_fight(request: FightRequest) -> void:
		requests.append(request)
		var result := FightResult.new(FightResult.Outcome.VICTORY, 1.0, {})
		Engine.get_main_loop().process_frame.connect(func() -> void: finished.emit(result), CONNECT_ONE_SHOT)


class OneBot:
	extends SquadProvider

	func get_squad() -> Array[SquadMemberSummary]:
		var squad: Array[SquadMemberSummary] = [SquadMemberSummary.new("solo", "Solo", 10, 10, "", UnitStats.new(10, 1, 1, 1, 1, 1))]
		return squad


var _tuning: MapTuning


func before_test() -> void:
	_tuning = MapTuning.load_file(TUNING)


func _campaign(map_path := ACT1) -> Campaign:
	return Campaign.new(RegionMap.load_file(map_path), _tuning, StubSquadProvider.new(), StubFightService.new())


func _pair_map(b_owned: bool) -> RegionMap:
	return RegionMap.from_dict({
		"id": "pair", "name": "Pair",
		"regions": [
			{"id": "a", "name": "A", "kind": "T", "polygon": [[0, 0], [0.5, 0], [0.5, 1]], "adjacent": ["b"],
				"provides": {"power": 0, "energy": 0, "material": 0}, "defense": 0, "pressure_base": 1, "starts_owned": true},
			{"id": "b", "name": "B", "kind": "T", "polygon": [[0.5, 0], [1, 0], [1, 1]], "adjacent": ["a"],
				"provides": {"power": 0, "energy": 0, "material": 0}, "defense": 2, "pressure_base": 1, "starts_owned": b_owned},
		],
	})


func test_a_new_run_starts_from_the_region_file_and_tuning() -> void:
	var c := _campaign()
	assert_array(Array(c.state.owned)).contains_exactly(["aurora_data_center", "substation_9"])
	assert_float(c.pressure_of("aurora_data_center")).is_equal(0.0)
	assert_float(c.state.grid).is_equal(100.0)
	assert_int(c.state.time_points).is_equal(0)
	assert_int(c.day()).is_equal(1)
	assert_int(c.days_left()).is_equal(100)


func test_standing_follows_adjacency() -> void:
	var c := _campaign()
	assert_int(c.standing("aurora_data_center")).is_equal(Campaign.Standing.OWNED)
	assert_int(c.standing("hydro_dam")).is_equal(Campaign.Standing.IN_RANGE)
	assert_int(c.standing("refinery_row")).is_equal(Campaign.Standing.IN_RANGE)
	assert_int(c.standing("ridge_relay")).is_equal(Campaign.Standing.OUT_OF_REACH)
	assert_int(c.standing("military_depot")).is_equal(Campaign.Standing.OUT_OF_REACH)


func test_a_region_out_of_reach_cannot_be_attacked() -> void:
	var c := _campaign()
	assert_bool(c.can_attack("ridge_relay")).is_false()
	assert_bool(await c.attack("ridge_relay")).is_false()
	assert_int(c.state.time_points).is_equal(0)
	assert_bool(c.is_owned("ridge_relay")).is_false()


func test_a_held_region_cannot_be_attacked_and_a_hostile_one_cannot_be_reinforced() -> void:
	var c := _campaign()
	assert_bool(c.can_attack("aurora_data_center")).is_false()
	assert_bool(c.reinforce("hydro_dam")).is_false()


func test_action_time_costs() -> void:
	var c := _campaign()
	assert_int(c.time_cost(Campaign.Action.ATTACK)).is_equal(3)
	assert_int(c.time_cost(Campaign.Action.REINFORCE)).is_equal(1)
	assert_int(c.time_cost(Campaign.Action.WAIT)).is_equal(1)
	assert_int(c.action_for("hydro_dam")).is_equal(Campaign.Action.ATTACK)
	assert_int(c.action_for("aurora_data_center")).is_equal(Campaign.Action.REINFORCE)
	assert_int(c.action_for("ridge_relay")).is_equal(Campaign.Action.NONE)


func test_pressure_rate_is_base_plus_per_level_times_border() -> void:
	var c := _campaign()
	assert_float(c.pressure_rate("aurora_data_center")).is_equal_approx(1.8, 1e-9)
	assert_float(c.pressure_rate("substation_9")).is_equal_approx(2.7, 1e-9)
	var interior := Campaign.new(_pair_map(true), _tuning, StubSquadProvider.new(), StubFightService.new())
	assert_bool(interior.is_border("a")).is_false()
	assert_float(interior.pressure_rate("a")).is_equal_approx(1.2, 1e-9)


func test_waiting_builds_pressure_and_accrues_income() -> void:
	var c := _campaign()
	c.state.grid = 50.0
	assert_bool(c.wait()).is_true()
	assert_int(c.state.time_points).is_equal(1)
	assert_float(c.pressure_of("aurora_data_center")).is_equal_approx(1.8, 1e-9)
	assert_float(c.pressure_of("substation_9")).is_equal_approx(2.7, 1e-9)
	# Held grid power is 2 + 4; it regenerates by that divided by 4 each point.
	assert_float(c.state.grid).is_equal_approx(51.5, 1e-9)
	# Energy 3 a day is 3/4 a point, on top of the starting stock.
	assert_float(c.state.energy).is_equal_approx(_tuning.start_energy + 0.75, 1e-9)
	assert_float(c.state.material).is_equal(0.0)


func test_grid_does_not_regenerate_past_full() -> void:
	var c := _campaign()
	c.wait()
	assert_float(c.state.grid).is_equal(100.0)


func test_four_points_make_a_day() -> void:
	var c := _campaign()
	for i in 4:
		c.wait()
	assert_int(c.day()).is_equal(2)
	assert_int(c.days_left()).is_equal(99)


func test_reinforce_removes_pressure_and_costs_time_and_grid() -> void:
	var c := _campaign()
	c.state.pressure["substation_9"] = 60.0
	assert_bool(c.reinforce("substation_9")).is_true()
	assert_float(c.pressure_of("substation_9")).is_equal_approx(60.0 - 45.0 + 2.7, 1e-9)
	assert_int(c.state.time_points).is_equal(1)
	# 100 - 2, then regenerates 6/4.
	assert_float(c.state.grid).is_equal_approx(99.5, 1e-9)


func test_reinforce_does_not_go_below_zero() -> void:
	var c := _campaign()
	c.state.pressure["aurora_data_center"] = 10.0
	c.reinforce("aurora_data_center")
	assert_float(c.pressure_of("aurora_data_center")).is_equal_approx(1.8, 1e-9)


func test_an_ignored_border_region_forces_a_defensive_fight() -> void:
	var c := _campaign()
	# Substation 9 gains 2.7 a point: 37 points leave it short of 100, 38 fill it.
	for i in 37:
		assert_bool(c.wait()).is_true()
	assert_str(c.pending_defense()).is_empty()
	c.wait()
	assert_str(c.pending_defense()).is_equal("substation_9")
	assert_float(c.pressure_of("substation_9")).is_equal(100.0)
	assert_bool(c.can_act()).is_false()
	assert_bool(c.wait()).is_false()
	assert_bool(c.reinforce("aurora_data_center")).is_false()
	assert_int(c.state.time_points).is_equal(38)


func test_the_cause_names_the_strongest_hostile_neighbor() -> void:
	var c := _campaign()
	assert_int(c.cause_of("substation_9")).is_equal(Campaign.Cause.ATTACK)
	# Downtown Exchange (defense 4) beats Refinery Row (defense 3).
	assert_str(c.attacker_of("substation_9").id).is_equal("downtown_exchange")
	var surrounded := Campaign.new(_pair_map(true), _tuning, StubSquadProvider.new(), StubFightService.new())
	assert_int(surrounded.cause_of("a")).is_equal(Campaign.Cause.UPRISING)
	assert_object(surrounded.attacker_of("a")).is_null()


func test_losing_a_forced_defense_loses_the_region() -> void:
	var c := _campaign()
	c.state.pressure["substation_9"] = 100.0
	var fights := []
	c.fight_started.connect(func(r: FightRequest) -> void: fights.append(r))
	assert_bool(await c.defend()).is_true()
	assert_int(fights.size()).is_equal(1)
	assert_int(fights[0].kind).is_equal(FightRequest.Kind.DEFEND)
	# The stub loses above level 3; Downtown Exchange attacks at 4.
	assert_int(fights[0].defense_level).is_equal(4)
	assert_bool(c.is_owned("substation_9")).is_false()
	assert_str(c.pending_defense()).is_empty()
	assert_float(c.state.grid).is_equal_approx(100.0 - 12.0, 1e-9)
	assert_int(c.state.time_points).is_equal(0)


func test_winning_a_forced_defense_eases_pressure() -> void:
	var c := _campaign()
	c.state.pressure["aurora_data_center"] = 100.0
	# Aurora's strongest hostile neighbor is Hydro Dam or Foundry District, both 3.
	assert_bool(await c.defend()).is_true()
	assert_bool(c.is_owned("aurora_data_center")).is_true()
	assert_float(c.pressure_of("aurora_data_center")).is_equal(30.0)
	assert_bool(c.can_act()).is_true()


func test_an_uprising_is_fought_at_the_tuned_level() -> void:
	var c := Campaign.new(_pair_map(true), _tuning, StubSquadProvider.new(), StubFightService.new())
	c.state.pressure["a"] = 100.0
	var levels := []
	c.fight_started.connect(func(r: FightRequest) -> void: levels.append(r.defense_level))
	await c.defend()
	assert_array(levels).contains_exactly([2])


func test_winning_an_attack_captures_the_region() -> void:
	var c := _campaign()
	assert_bool(await c.attack("hydro_dam")).is_true()
	assert_bool(c.is_owned("hydro_dam")).is_true()
	assert_int(c.state.time_points).is_equal(3)
	# 15 after capture, then 3 points at (0.6 + 0.6 x 2) x 1.5.
	assert_float(c.pressure_of("hydro_dam")).is_equal_approx(15.0 + 3 * 2.7, 1e-9)
	# 100 - (4 + 2 x 3), then 3 points of (2 + 4 + 5) / 4.
	assert_float(c.state.grid).is_equal_approx(90.0 + 3 * 11.0 / 4.0, 1e-9)
	assert_float(c.state.energy).is_equal_approx(_tuning.start_energy + 10.0 + 3 * 3.0 / 4.0, 1e-9)
	assert_float(c.state.material).is_equal_approx(5.0, 1e-9)
	assert_int(c.standing("ridge_relay")).is_equal(Campaign.Standing.IN_RANGE)
	assert_array(Array(c.state.owned)).contains_exactly(["hydro_dam", "aurora_data_center", "substation_9"])


func test_losing_an_attack_costs_one_and_a_half_times_the_grid() -> void:
	var c := _campaign()
	assert_bool(await c.attack("downtown_exchange")).is_true()
	assert_bool(c.is_owned("downtown_exchange")).is_false()
	assert_int(c.state.time_points).is_equal(3)
	# (4 + 2 x 4) x 1.5 = 18, then 3 points of 6 / 4.
	assert_float(c.state.grid).is_equal_approx(82.0 + 3 * 1.5, 1e-9)
	# A lost battle also takes stakes.loss_cost and counts toward the limit.
	assert_float(c.state.energy).is_equal_approx(_tuning.start_energy - c.stakes.loss_cost["energy"] + 3 * 0.75, 1e-9)
	assert_int(c.state.losses).is_equal(1)


func test_the_attack_request_carries_the_squad_and_defense() -> void:
	var c := _campaign()
	var requests := []
	c.fight_started.connect(func(r: FightRequest) -> void: requests.append(r))
	await c.attack("refinery_row")
	var r: FightRequest = requests[0]
	assert_int(r.kind).is_equal(FightRequest.Kind.ATTACK)
	assert_str(r.territory_id).is_equal("refinery_row")
	assert_int(r.defense_level).is_equal(3)
	assert_int(r.squad.size()).is_equal(4)


func test_other_squad_and_fight_implementations_swap_in_unchanged() -> void:
	var service := AlwaysWins.new()
	var c := Campaign.new(RegionMap.load_file(ACT1), _tuning, OneBot.new(), service)
	assert_bool(await c.attack("downtown_exchange")).is_true()
	assert_bool(c.is_owned("downtown_exchange")).is_true()
	assert_int(service.requests.size()).is_equal(1)
	assert_str(service.requests[0].squad[0].id).is_equal("solo")


func test_no_action_while_a_fight_is_out() -> void:
	var c := _campaign()
	# Called without await, so the test can look while the fight is out.
	c.attack.call("hydro_dam")
	assert_bool(c.fighting).is_true()
	assert_bool(c.can_act()).is_false()
	assert_bool(c.wait()).is_false()
	await assert_signal(c).wait_until(2000).is_emitted("changed")
	assert_bool(c.fighting).is_false()
	assert_bool(c.is_owned("hydro_dam")).is_true()


func test_odds_compare_squad_level_with_defense() -> void:
	var c := _campaign()
	# Stub squad: attack + defense sums to 42, which is level 3 at 14 a level.
	assert_int(c.squad_level()).is_equal(3)
	assert_str(c.odds_label("solar_fields")).is_equal("Favored")
	assert_str(c.odds_label("hydro_dam")).is_equal("Even")
	assert_str(c.odds_label("downtown_exchange")).is_equal("Risky")
	assert_str(c.odds_label("military_depot")).is_equal("Outmatched")


func test_the_pressure_scale_multiplies_every_rate() -> void:
	var c := _campaign()
	c.tuning = MapTuning.load_file(TUNING)
	c.tuning.pressure_scale = 0.5
	assert_float(c.pressure_rate("aurora_data_center")).is_equal_approx(0.9, 1e-9)
	assert_float(c.pressure_rate("substation_9")).is_equal_approx(1.35, 1e-9)


func test_the_boss_fight_waits_for_the_payload() -> void:
	var c := _campaign()
	assert_object(await c.boss_fight()).is_null()


func test_the_boss_fight_goes_through_the_fight_service() -> void:
	var service := AlwaysWins.new()
	var c := Campaign.new(RegionMap.load_file(ACT1), _tuning, StubSquadProvider.new(), service)
	c.state.time_points = _tuning.total_points
	var logged: Array[String] = []
	c.event_logged.connect(func(text: String) -> void: logged.append(text))
	var result := await c.boss_fight()
	assert_bool(result.is_victory()).is_true()
	assert_int(service.requests.size()).is_equal(1)
	assert_str(service.requests[0].territory_id).is_equal(Campaign.BOSS_ID)
	assert_int(service.requests[0].defense_level).is_equal(_tuning.boss_defense_level)
	assert_array(logged).contains(["The boss is beaten."])
	# The stub service loses at level 5.
	var stub := _campaign()
	stub.state.time_points = _tuning.total_points
	assert_bool((await stub.boss_fight()).is_victory()).is_false()


func test_the_countdown_ends_at_the_payload() -> void:
	var c := _campaign()
	c.state.time_points = 398
	for region_id in c.state.owned:
		c.state.pressure[region_id] = 0.0
	assert_bool(await c.attack("hydro_dam")).is_true()
	assert_int(c.state.time_points).is_equal(400)
	assert_bool(c.is_payload_due()).is_true()
	assert_int(c.day()).is_equal(100)
	assert_int(c.days_left()).is_equal(0)
	assert_bool(c.can_act()).is_false()
	assert_bool(c.wait()).is_false()


func test_losing_every_region_ends_the_run() -> void:
	var c := Campaign.new(_pair_map(false), _tuning, StubSquadProvider.new(), StubFightService.new())
	c.apply_defense_result("a", FightResult.new(FightResult.Outcome.DEFEAT, 0.0, {}))
	assert_bool(c.is_lost()).is_true()
	assert_bool(c.can_act()).is_false()


func test_the_same_map_code_runs_another_region_file() -> void:
	var c := _campaign("res://data/regions/harbor_town_placeholder.json")
	assert_int(c.standing("north_pier")).is_equal(Campaign.Standing.IN_RANGE)
	assert_int(c.standing("rail_yard")).is_equal(Campaign.Standing.IN_RANGE)
	assert_int(c.standing("garrison")).is_equal(Campaign.Standing.OUT_OF_REACH)
	assert_int(c.standing("lighthouse")).is_equal(Campaign.Standing.OUT_OF_REACH)
	assert_bool(await c.attack("north_pier")).is_true()
	assert_bool(c.is_owned("north_pier")).is_true()
