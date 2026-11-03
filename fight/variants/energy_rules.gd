class_name EnergyRules
extends RefCounted
## What the basic attack costs and how fast energy comes back, by the
## strike-cost switch (FightVariants). Every rule is deterministic.
##
## Decided Nov 2: every action costs energy except Wait, which stays free and
## always available. Strike's cost is its energy_cost in
## data/combat/actions.json, like any other action's.
##
##   costs  the decided rule: Strike costs what actions.json says, and energy
##          recharges by the option's own recharge_milli_per_battery_per_tick
##          and recharge_floor_milli_per_tick, so a bot chooses between
##          Strike, a bigger skill and waiting
##   free   the retired rule, kept so tools can compare old and new on the
##          same seeds: Strike costs 0 whatever the data says, and energy
##          recharges by energy.recharge_milli_per_battery_per_tick in
##          combat_tuning.json


## True when the retired free-Strike rule is chosen.
static func strike_free(tuning: CombatTuning) -> bool:
	return tuning.variants == null or tuning.variants.is_chosen(FightVariants.STRIKE_COST, FightVariants.STRIKE_FREE)


## The energy cost of skill `id` whose data cost is `data_cost`.
static func cost_of(id: String, data_cost: int, tuning: CombatTuning) -> int:
	if id == tuning.basic_attack and not id.is_empty() and strike_free(tuning):
		return 0
	return data_cost


## Recharge per tick per battery point, in thousandths.
static func recharge_milli_per_battery(tuning: CombatTuning) -> int:
	if strike_free(tuning):
		return tuning.recharge_milli_per_battery_per_tick
	return tuning.variants.param_int(FightVariants.STRIKE_COST, "recharge_milli_per_battery_per_tick",
		tuning.recharge_milli_per_battery_per_tick)


## The least recharge per tick, in thousandths.
static func recharge_floor_milli(tuning: CombatTuning) -> int:
	if strike_free(tuning):
		return tuning.recharge_floor_milli_per_tick
	return maxi(1, tuning.variants.param_int(FightVariants.STRIKE_COST, "recharge_floor_milli_per_tick",
		tuning.recharge_floor_milli_per_tick))
