extends GdUnitTestSuite
## Stakes and economy (Campaign with Stakes), headless on the act 1
## placeholder map: the loss limit, the cost of losing, retreat, breach,
## repair, what reinforcing costs, and fast-forward.

const ACT1 := "res://data/regions/act1_placeholder.json"
const TUNING := "res://data/tuning/overworld.json"


class Fixed:
	extends FightService
	var win := false
	var requests: Array[FightRequest] = []

	func start_fight(request: FightRequest) -> void:
		requests.append(request)
		var result := FightResult.new(FightResult.Outcome.VICTORY if win else FightResult.Outcome.DEFEAT, 1.0, {})
		Engine.get_main_loop().process_frame.connect(func() -> void: finished.emit(result), CONNECT_ONE_SHOT)


var _tuning: MapTuning
var _service: Fixed


func before_test() -> void:
	_tuning = MapTuning.load_file(TUNING)
	_service = Fixed.new()


func _campaign(choices: Dictionary = {}) -> Campaign:
	var v := CampaignVariants.defaults()
	for decision: String in choices:
		v.choose(decision, choices[decision])
	var map := RegionMap.load_file(ACT1)
	var state := Campaign.new_run_state(map, _tuning, null, v)
	return Campaign.new(map, _tuning, StubSquadProvider.new(), _service, state)


func _lose_attack(c: Campaign) -> void:
	_service.win = false
	assert_bool(await c.attack("hydro_dam")).is_true()


func test_the_tuning_and_switchboard_give_every_number() -> void:
	var c := _campaign()
	assert_array(c.stakes.errors).is_empty()
	assert_int(c.stakes.loss_limit).is_equal(3)
	assert_float(c.stakes.loss_cost[Stakes.ENERGY]).is_greater(0.0)
	assert_float(c.stakes.cost(Stakes.USE_RETREAT)[Stakes.ENERGY]).is_greater(0.0)
	assert_float(c.stakes.cost(Stakes.USE_BREACH)[Stakes.MATERIAL]).is_greater(0.0)
	assert_float(c.stakes.cost(Stakes.USE_REPAIR)[Stakes.MATERIAL]).is_greater(0.0)
	assert_float(c.stakes.cost(Stakes.USE_REINFORCE)[Stakes.ENERGY]).is_greater(0.0)
	assert_int(c.losses_left()).is_equal(3)


func test_a_lost_battle_costs_resources_and_counts() -> void:
	var c := _campaign()
	c.state.energy = 50.0
	c.state.material = 20.0
	await _lose_attack(c)
	assert_int(c.state.losses).is_equal(1)
	assert_int(c.losses_left()).is_equal(2)
	assert_float(c.state.material).is_equal_approx(20.0 - c.stakes.loss_cost[Stakes.MATERIAL], 1e-9)
	assert_bool(c.is_over()).is_false()


func test_a_loss_takes_no_more_than_there_is() -> void:
	var c := _campaign()
	c.state.energy = 1.0
	c.state.material = 0.0
	await _lose_attack(c)
	assert_float(c.state.material).is_equal(0.0)
	assert_float(c.state.energy).is_greater_equal(0.0)


func test_the_third_loss_in_an_act_ends_the_run() -> void:
	var c := _campaign()
	await _lose_attack(c)
	await _lose_attack(c)
	assert_bool(c.is_defeated()).is_false()
	await _lose_attack(c)
	assert_bool(c.is_defeated()).is_true()
	assert_bool(c.is_over()).is_true()
	assert_str(c.end_reason()).is_equal(Stakes.END_LOSS_LIMIT)
	assert_bool(c.can_act()).is_false()


func test_a_lost_defense_counts_too() -> void:
	var c := _campaign({CampaignVariants.LOSS_LIMIT: CampaignVariants.LOSSES_ONE})
	c.state.pressure["substation_9"] = _tuning.forces_defense_at
	_service.win = false
	assert_bool(await c.defend()).is_true()
	assert_str(c.end_reason()).is_equal(Stakes.END_LOSS_LIMIT)


func test_unlimited_losses_never_end_the_run() -> void:
	var c := _campaign({CampaignVariants.LOSS_LIMIT: CampaignVariants.LOSSES_UNLIMITED})
	for i in 4:
		await _lose_attack(c)
	assert_int(c.state.losses).is_equal(4)
	assert_int(c.losses_left()).is_equal(-1)
	assert_bool(c.is_defeated()).is_false()


## loss-count attacks_only: a lost forced defense costs the region, not a loss.
func test_attacks_only_does_not_count_a_lost_defense() -> void:
	var c := _campaign({CampaignVariants.LOSS_COUNT: CampaignVariants.LOSS_COUNT_ATTACKS_ONLY})
	assert_bool(c.stakes.defense_losses_count).is_false()
	var held: String = c.state.owned[0]
	c.apply_defense_result(held, FightResult.new(FightResult.Outcome.DEFEAT, 0.0, {} as Dictionary[String, int]))
	assert_bool(held in c.state.owned).is_false()
	assert_int(c.state.losses).is_equal(0)
	var d := _campaign()
	var held_d: String = d.state.owned[0]
	d.apply_defense_result(held_d, FightResult.new(FightResult.Outcome.DEFEAT, 0.0, {} as Dictionary[String, int]))
	assert_int(d.state.losses).is_equal(1)


## loss-limit scaled: longer acts allow more losses, never fewer than min_limit.
func test_the_scaled_limit_grows_with_the_act() -> void:
	var v := CampaignVariants.defaults()
	assert_bool(v.choose(CampaignVariants.LOSS_LIMIT, CampaignVariants.LOSSES_SCALED)).is_true()
	var p := v.params(CampaignVariants.LOSS_LIMIT)
	for act in 3:
		var expected := ceili(float(p.expected_fights[act]) / float(p.fights_per_loss))
		assert_int(Stakes.loss_limit_for(v, act)).is_equal(maxi(int(p.min_limit), expected))
		assert_int(Stakes.loss_limit_for(v, act)).is_greater_equal(int(p.min_limit))
	assert_int(Stakes.loss_limit_for(v, 1)).is_greater_equal(Stakes.loss_limit_for(v, 0))
	var c := _campaign({CampaignVariants.LOSS_LIMIT: CampaignVariants.LOSSES_SCALED})
	assert_int(c.stakes.loss_limit).is_equal(Stakes.loss_limit_for(v, c.state.act))
	assert_int(Stakes.loss_limit_for(CampaignVariants.defaults(), 1)).is_equal(3)


func test_losing_the_boss_fight_ends_the_run_and_winning_wins_it() -> void:
	var c := _campaign()
	c.state.time_points = _tuning.total_points
	_service.win = false
	assert_object(await c.boss_fight()).is_not_null()
	assert_str(c.end_reason()).is_equal(Stakes.END_BOSS_LOST)
	assert_bool(c.is_defeated()).is_true()
	var w := _campaign()
	w.state.time_points = _tuning.total_points
	_service.win = true
	await w.boss_fight()
	assert_str(w.end_reason()).is_equal(Stakes.END_WON)
	assert_bool(w.is_defeated()).is_false()


func test_retreating_from_an_attack_costs_energy_and_time_and_fights_nothing() -> void:
	var c := _campaign()
	c.state.energy = 30.0
	var acted: Array = []
	c.acted.connect(func(a: Campaign.Action, id: String) -> void: acted.append([a, id]))
	assert_bool(c.retreat("hydro_dam")).is_true()
	assert_array(_service.requests).is_empty()
	assert_int(c.state.time_points).is_equal(c.stakes.retreat_attack_time)
	var income := c.income_per_day()[MapRegion.ENERGY] * float(c.stakes.retreat_attack_time) / _tuning.points_per_day
	assert_float(c.state.energy).is_equal_approx(30.0 - c.stakes.cost(Stakes.USE_RETREAT)[Stakes.ENERGY] + income, 1e-9)
	assert_int(c.state.losses).is_equal(0)
	assert_array(acted).is_equal([[Campaign.Action.RETREAT, "hydro_dam"]])


func test_retreat_needs_the_energy_and_a_fight_to_back_out_of() -> void:
	var c := _campaign()
	c.state.energy = 0.0
	assert_bool(c.can_retreat("hydro_dam")).is_false()
	c.state.energy = 30.0
	assert_bool(c.can_retreat("ridge_relay")).is_false()
	assert_bool(c.can_retreat("aurora_data_center")).is_false()


func test_retreating_from_a_forced_defense_gives_the_region_up() -> void:
	var c := _campaign()
	c.state.energy = 30.0
	c.state.pressure["substation_9"] = _tuning.forces_defense_at
	assert_bool(c.can_retreat("hydro_dam")).is_false()
	assert_bool(c.retreat("substation_9")).is_true()
	assert_bool(c.is_owned("substation_9")).is_false()
	assert_int(c.state.losses).is_equal(0)
	assert_array(_service.requests).is_empty()
	assert_str(c.pending_defense()).is_empty()


func test_a_breach_lowers_the_fight_and_costs_material() -> void:
	var c := _campaign()
	c.state.material = 10.0
	assert_bool(c.can_breach("hydro_dam")).is_true()
	_service.win = true
	assert_bool(await c.attack("hydro_dam", true)).is_true()
	assert_int(_service.requests[0].defense_level).is_equal(3 - c.stakes.breach_levels)
	assert_bool(c.breached).is_true()
	assert_float(c.state.material).is_less(10.0)


func test_a_breach_needs_material_and_defense_to_take_off() -> void:
	var c := _campaign()
	c.state.material = 0.0
	assert_bool(c.can_breach("hydro_dam")).is_false()
	assert_bool(await c.attack("hydro_dam", true)).is_false()
	assert_array(_service.requests).is_empty()


func test_repair_turns_material_into_grid() -> void:
	var c := _campaign()
	c.state.material = 10.0
	c.state.grid = 50.0
	assert_bool(c.repair()).is_true()
	assert_float(c.state.grid).is_equal_approx(50.0 + c.stakes.repair_grid, 1e-9)
	assert_float(c.state.material).is_equal_approx(10.0 - c.stakes.cost(Stakes.USE_REPAIR)[Stakes.MATERIAL], 1e-9)
	assert_int(c.state.time_points).is_equal(0)
	c.state.material = 0.0
	assert_bool(c.can_repair()).is_false()


func test_reinforcing_costs_energy_and_needs_it() -> void:
	var c := _campaign()
	c.state.energy = 10.0
	assert_bool(c.reinforce("substation_9")).is_true()
	assert_float(c.state.energy).is_less(10.0)
	c.state.energy = 0.0
	assert_bool(c.can_reinforce("substation_9")).is_false()


func test_the_swapped_option_moves_the_costs() -> void:
	var c := _campaign({CampaignVariants.RESOURCE_USES: CampaignVariants.USES_SWAPPED})
	assert_float(c.stakes.cost(Stakes.USE_REINFORCE)[Stakes.ENERGY]).is_equal(0.0)
	assert_float(c.stakes.cost(Stakes.USE_REINFORCE)[Stakes.MATERIAL]).is_greater(0.0)
	assert_float(c.stakes.cost(Stakes.USE_BREACH)[Stakes.ENERGY]).is_greater(0.0)
	c.state.energy = 0.0
	c.state.material = 10.0
	assert_bool(c.reinforce("substation_9")).is_true()
	assert_float(c.state.material).is_less(10.0)


func test_fast_forward_waits_until_nothing_is_in_range() -> void:
	var c := _campaign()
	assert_bool(c.can_fast_forward()).is_false()
	assert_dict(c.fast_forward()).is_empty()


func test_fast_forward_plays_to_the_payload_once_the_map_is_taken() -> void:
	var c := _campaign()
	c.state.owned = RegionMap.load_file(ACT1).ids()
	for id in c.state.owned:
		c.state.pressure[id] = 0.0
	c.state.energy = 10000.0
	assert_bool(c.can_fast_forward()).is_true()
	var summary := c.fast_forward()
	assert_bool(c.is_payload_due()).is_true()
	assert_str(str(summary.stopped)).is_equal("payload")
	assert_float(float(summary.days)).is_greater(0.0)
	# Pressure built on every region over the act; auto-reinforce held it off.
	assert_int(int(summary.reinforced)).is_greater(0)
	assert_str(c.pending_defense()).is_empty()


func test_fast_forward_stops_at_a_forced_defense() -> void:
	var c := _campaign()
	c.state.owned = RegionMap.load_file(ACT1).ids()
	for id in c.state.owned:
		c.state.pressure[id] = _tuning.forces_defense_at - 0.1
	c.state.energy = 0.0
	var summary := c.fast_forward()
	assert_str(str(summary.stopped)).is_equal("defense")
	assert_str(c.pending_defense()).is_not_empty()
	assert_bool(c.is_payload_due()).is_false()


func test_losses_and_the_end_are_saved_and_reset_by_the_zoom() -> void:
	var c := _campaign()
	c.state.losses = 2
	c.state.ended = Stakes.END_LOSS_LIMIT
	var back := RunState.from_dict(c.state.to_dict())
	assert_int(back.losses).is_equal(2)
	assert_str(back.ended).is_equal(Stakes.END_LOSS_LIMIT)
	var plan := ActPlan.load_file("res://data/tuning/acts.json")
	var next_map := plan.load_map(1)
	var zoomed := plan.zoom_state(back, next_map, plan.load_tuning(1))
	assert_int(zoomed.losses).is_equal(0)
	assert_str(zoomed.ended).is_empty()
	var old := c.state.to_dict()
	old.erase("losses")
	old.erase("ended")
	assert_int(RunState.from_dict(old).losses).is_equal(0)


func test_shared_pool_pays_energy_from_the_pool() -> void:
	var c := _campaign({CampaignVariants.ENERGY_GRID: CampaignVariants.ENERGY_SHARED_POOL})
	c.state.grid = 60.0
	assert_bool(c.retreat("hydro_dam")).is_true()
	assert_float(c.state.grid).is_less(60.0)
