class_name EnergyRules
extends RefCounted
## What the basic attack costs and how fast energy comes back, by the
## strike-cost switch (FightVariants). Every rule is deterministic.
##
##   free   Strike costs what combat_tuning.json says (0), and energy recharges
##          by energy.recharge_milli_per_battery_per_tick (the old rule)
##   costs  Strike costs energy_cost, and energy recharges by the option's own
##          recharge_milli_per_battery_per_tick and recharge_floor_milli_per_tick,
##          so a bot must choose between Strike, a bigger skill and waiting
##
## TODO(decision: strike-cost): Strike at 1 energy and the recharge with it are
## stand-ins until playtested.


static func strike_costs(tuning: CombatTuning) -> bool:
	return tuning.variants != null and tuning.variants.is_chosen(FightVariants.STRIKE_COST, FightVariants.STRIKE_COSTS)


## The energy cost of skill `id` whose data cost is `data_cost`.
static func cost_of(id: String, data_cost: int, tuning: CombatTuning) -> int:
	if id == tuning.basic_attack and not id.is_empty() and strike_costs(tuning):
		return maxi(0, tuning.variants.param_int(FightVariants.STRIKE_COST, "energy_cost", data_cost))
	return data_cost


## Recharge per tick per battery point, in thousandths.
static func recharge_milli_per_battery(tuning: CombatTuning) -> int:
	if strike_costs(tuning):
		return tuning.variants.param_int(FightVariants.STRIKE_COST, "recharge_milli_per_battery_per_tick",
			tuning.recharge_milli_per_battery_per_tick)
	return tuning.recharge_milli_per_battery_per_tick


## The least recharge per tick, in thousandths.
static func recharge_floor_milli(tuning: CombatTuning) -> int:
	if strike_costs(tuning):
		return maxi(1, tuning.variants.param_int(FightVariants.STRIKE_COST, "recharge_floor_milli_per_tick",
			tuning.recharge_floor_milli_per_tick))
	return tuning.recharge_floor_milli_per_tick
