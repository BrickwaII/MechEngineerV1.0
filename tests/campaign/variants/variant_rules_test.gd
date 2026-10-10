extends GdUnitTestSuite
## The campaign variant rules in play: energy-grid, grid-cost-owner and
## act-pacing, through Campaign.

const ACT1 := "res://data/regions/act1_placeholder.json"
const TUNING := "res://data/tuning/overworld.json"
const ACTS := "res://data/tuning/acts.json"


class Fixed:
	extends FightService
	var outcome: FightResult.Outcome
	var cost: float
	var rewards: Dictionary[String, int] = {}

	func _init(p_outcome: FightResult.Outcome, p_cost: float, p_rewards: Dictionary[String, int] = {}) -> void:
		outcome = p_outcome
		cost = p_cost
		rewards = p_rewards

	func start_fight(_request: FightRequest) -> void:
		var result := FightResult.new(outcome, cost, rewards)
		Engine.get_main_loop().process_frame.connect(func() -> void: finished.emit(result), CONNECT_ONE_SHOT)


func _variants(choices: Dictionary) -> CampaignVariants:
	var v := CampaignVariants.defaults()
	for id: String in choices:
		assert_bool(v.choose(id, choices[id])).is_true()
	return v


func _campaign(choices := {}, service: FightService = null) -> Campaign:
	var map := RegionMap.load_file(ACT1)
	var tuning := MapTuning.load_file(TUNING)
	var v := _variants(choices)
	var c := Campaign.new(map, tuning, StubSquadProvider.new(),
		service if service != null else StubFightService.new(), Campaign.new_run_state(map, tuning, null, v))
	c.next_fight_variants = func() -> CampaignVariants: return v
	return c


# --- energy-grid ------------------------------------------------------------------

func test_separate_keeps_todays_income_rules() -> void:
	var c := _campaign()
	var income := c.income_per_day()
	c.state.grid = 50.0
	c.wait()
	assert_float(c.state.energy).is_equal_approx(float(income[MapRegion.ENERGY]) / c.tuning.points_per_day, 0.0001)
	assert_float(c.state.grid).is_equal_approx(50.0 + income[MapRegion.POWER] / c.tuning.grid_regen_divisor, 0.0001)


func test_shared_pool_regens_from_power_and_energy_and_holds_no_energy() -> void:
	var c := _campaign({"energy-grid": "shared_pool"})
	var income := c.income_per_day()
	var divisor := c.variants.param_float(CampaignVariants.ENERGY_GRID, "pool_regen_divisor")
	c.state.grid = 50.0
	c.wait()
	assert_float(c.state.energy).is_equal(0.0)
	assert_float(c.state.grid).is_equal_approx(50.0 + (income[MapRegion.POWER] + income[MapRegion.ENERGY]) / divisor, 0.0001)


func test_shared_pool_turns_fight_energy_into_grid() -> void:
	var rewards: Dictionary[String, int] = {FightResult.ENERGY: 10}
	var c := _campaign({"energy-grid": "shared_pool"}, Fixed.new(FightResult.Outcome.VICTORY, 0.0, rewards))
	var per_energy := c.variants.param_float(CampaignVariants.ENERGY_GRID, "energy_to_pool")
	c.state.grid = 20.0
	c.apply_attack_result("hydro_dam", FightResult.new(FightResult.Outcome.VICTORY, 0.0, rewards))
	assert_float(c.state.energy).is_equal(0.0)
	assert_float(c.state.grid).is_greater_equal(20.0 + 10 * per_energy)


func test_the_pool_never_passes_max_grid() -> void:
	var c := _campaign({"energy-grid": "shared_pool"})
	for i in 40:
		c.wait()
	assert_float(c.state.grid).is_less_equal(c.tuning.max_grid)


func test_a_shared_pool_run_keeps_it_across_a_save() -> void:
	var c := _campaign({"energy-grid": "shared_pool"})
	var resumed := Campaign.new(c.map, MapTuning.load_file(TUNING), StubSquadProvider.new(), StubFightService.new(),
		RunState.from_dict(c.state.to_dict()))
	assert_bool(EnergyGridRules.is_shared(resumed.variants)).is_true()


# --- grid-cost-owner --------------------------------------------------------------

func _lost_attack_charge(option: String) -> float:
	var c := _campaign({"grid-cost-owner": option})
	var v := c.next_fight_variants.call() as CampaignVariants
	var raw := FightResult.new(FightResult.Outcome.DEFEAT, 10.0, {})
	# The fight service's part, then the map's.
	var reported := GridCostOwner.service_result(FightRequest.Kind.ATTACK, raw, v)
	return c.fight_grid_charge(FightRequest.Kind.ATTACK, reported)


func test_the_map_surcharge_is_todays_rule() -> void:
	assert_float(_lost_attack_charge("map_surcharge")).is_equal(10.0 * MapTuning.load_file(TUNING).defeat_grid_multiplier)


func test_the_fight_service_can_own_the_surcharge() -> void:
	var v := _variants({"grid-cost-owner": "fight_service"})
	var raw := FightResult.new(FightResult.Outcome.DEFEAT, 10.0, {})
	var reported := GridCostOwner.service_result(FightRequest.Kind.ATTACK, raw, v)
	assert_float(reported.grid_cost).is_equal(10.0 * v.param_float(CampaignVariants.GRID_COST_OWNER, "defeat_multiplier"))
	assert_float(_lost_attack_charge("fight_service")).is_equal(reported.grid_cost)


func test_no_surcharge_charges_a_defeat_like_a_victory() -> void:
	assert_float(_lost_attack_charge("no_surcharge")).is_equal(10.0)


func test_wins_and_defenses_never_get_a_surcharge() -> void:
	for option: String in CampaignVariants.KNOWN[CampaignVariants.GRID_COST_OWNER]:
		var v := _variants({"grid-cost-owner": option})
		var win := FightResult.new(FightResult.Outcome.VICTORY, 10.0, {})
		var held := FightResult.new(FightResult.Outcome.DEFEAT, 10.0, {})
		assert_float(GridCostOwner.service_result(FightRequest.Kind.ATTACK, win, v).grid_cost).is_equal(10.0)
		assert_float(GridCostOwner.service_result(FightRequest.Kind.DEFEND, held, v).grid_cost).is_equal(10.0)
		assert_float(GridCostOwner.map_charge(FightRequest.Kind.DEFEND, held, v, 1.5)).is_equal(10.0)


func test_the_owner_is_read_when_the_fight_starts() -> void:
	var at_start := _variants({"grid-cost-owner": "no_surcharge"})
	var later := _variants({"grid-cost-owner": "map_surcharge"})
	var switched := _campaign({}, Fixed.new(FightResult.Outcome.DEFEAT, 10.0))
	var calls := [0]
	switched.next_fight_variants = func() -> CampaignVariants:
		calls[0] += 1
		return at_start if calls[0] == 1 else later
	var surcharged := _campaign({}, Fixed.new(FightResult.Outcome.DEFEAT, 10.0))
	surcharged.next_fight_variants = func() -> CampaignVariants: return later
	await switched.attack("hydro_dam")
	await surcharged.attack("hydro_dam")
	assert_int(calls[0]).is_equal(1)
	assert_float(switched.state.grid - surcharged.state.grid).is_equal_approx(5.0, 0.0001)


# --- act-pacing -------------------------------------------------------------------

func _act_tuning(option: String, act: int) -> MapTuning:
	var plan := ActPlan.load_file(ACTS)
	return ActPacing.paced(plan.load_tuning(act), act, _variants({"act-pacing": option}))


func test_current_pacing_plays_the_act_files() -> void:
	var plan := ActPlan.load_file(ACTS)
	for act in plan.act_count():
		var file := plan.load_tuning(act)
		assert_int(_act_tuning("current", act).total_points).is_equal(file.total_points)


func test_even_pacing_gives_every_act_the_same_clock() -> void:
	for act in 3:
		var t := _act_tuning("even", act)
		assert_array(t.errors).is_empty()
		assert_int(t.total_points).is_equal(400)
		assert_int(t.attack_time).is_equal(3)


func test_faster_later_acts_keep_the_total() -> void:
	var total := 0
	var lengths: Array[int] = []
	for act in 3:
		var t := _act_tuning("faster_later", act)
		assert_array(t.errors).is_empty()
		lengths.append(t.total_points)
		total += t.total_points
	var current := 0
	for act in 3:
		current += _act_tuning("current", act).total_points
	assert_int(total).is_equal(current)
	assert_int(lengths[1]).is_less(lengths[0])
	assert_int(lengths[2]).is_less(lengths[0])


func test_a_campaign_paces_its_act_and_the_zoom_keeps_the_choice() -> void:
	var plan := ActPlan.load_file(ACTS)
	var v := _variants({"act-pacing": "faster_later"})
	var map := plan.load_map(0)
	var c := Campaign.new(map, plan.load_tuning(0), StubSquadProvider.new(), StubFightService.new(),
		Campaign.new_run_state(map, plan.load_tuning(0), null, v))
	assert_int(c.tuning.total_points).is_equal(480)
	assert_int(c.days_left()).is_equal(120)
	var next_map := plan.load_map(1)
	var next_tuning := plan.load_tuning(1)
	var next := Campaign.new(next_map, next_tuning, StubSquadProvider.new(), StubFightService.new(),
		plan.zoom_state(c.state, next_map, next_tuning))
	assert_int(next.tuning.total_points).is_equal(360)


func test_overrides_lay_over_a_tuning_without_touching_it() -> void:
	var t := MapTuning.load_file(TUNING)
	var faster := t.with_overrides({"time": {"total_points": 200}})
	assert_int(faster.total_points).is_equal(200)
	assert_int(faster.attack_time).is_equal(t.attack_time)
	assert_int(t.total_points).is_equal(400)
