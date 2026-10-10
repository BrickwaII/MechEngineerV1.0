class_name EnergyGridRules
extends RefCounted
## The energy-grid decision: whether Energy and grid capacity are two
## resources or one. TODO(decision: energy-grid).
##
## separate (the default, today's rules):
##   Energy is a stock. Held regions add their energy per day, spread over the
##   day's points, and won fights add their energy reward. Nothing spends it
##   yet. Grid capacity (percent, 0 to max_grid) regains power per day over
##   grid.regen_divisor each point; attacks, reinforcing and lost fights spend
##   it (MapTuning's grid costs).
##
## shared_pool: grid capacity and Energy are one resource, the pool, kept in
##   RunState.grid in grid percent; RunState.energy stays 0.
##   - Start: the pool starts at grid.start plus the start's energy times
##     energy_to_pool, capped at max_grid.
##   - Regen: each point the pool regains (power + energy per day of the held
##     regions and the start's bonus) / pool_regen_divisor, capped at max_grid.
##   - Rewards: a won fight's energy reward adds energy_to_pool percent per
##     point of energy, capped at max_grid.
##   - Spend: exactly what grid spends today (attack, reinforce, defeat).
##   pool_regen_divisor and energy_to_pool are this option's params in
##   data/variants/variants.json.


static func is_shared(v: CampaignVariants) -> bool:
	return v.is_chosen(CampaignVariants.ENERGY_GRID, CampaignVariants.ENERGY_SHARED_POOL)


## Moves a new run's starting energy into the pool when the pool is shared.
static func start(state: RunState, tuning: MapTuning, v: CampaignVariants) -> void:
	if not is_shared(v):
		return
	state.grid = minf(tuning.max_grid, state.grid + state.energy * _energy_to_pool(v))
	state.energy = 0.0


## One time point's income: energy stock and grid regen, or the pool's regen.
## `income` is Campaign.income_per_day().
static func accrue_point(state: RunState, income: Dictionary, tuning: MapTuning, v: CampaignVariants) -> void:
	var power := float(income[MapRegion.POWER])
	var energy := float(income[MapRegion.ENERGY])
	if is_shared(v):
		var divisor := v.param_float(CampaignVariants.ENERGY_GRID, "pool_regen_divisor", 1.0)
		state.grid = minf(tuning.max_grid, state.grid + (power + energy) / maxf(divisor, 0.001))
		return
	state.energy += energy / tuning.points_per_day
	state.grid = minf(tuning.max_grid, state.grid + power / tuning.grid_regen_divisor)


## Adds energy won in a fight: to the stock, or to the pool.
static func add_energy(state: RunState, amount: float, tuning: MapTuning, v: CampaignVariants) -> void:
	if is_shared(v):
		state.grid = minf(tuning.max_grid, state.grid + amount * _energy_to_pool(v))
	else:
		state.energy += amount


static func _energy_to_pool(v: CampaignVariants) -> float:
	return v.param_float(CampaignVariants.ENERGY_GRID, "energy_to_pool", 0.0)
