class_name GridCostOwner
extends RefCounted
## The grid-cost-owner decision: who makes a lost attack cost more grid than a
## won one. Read when each fight starts. TODO(decision: grid-cost-owner).
##
## map_surcharge (the default, today's rule): the fight service charges the
##   same on victory and defeat, and the map multiplies a lost attack's cost
##   by grid.defeat_multiplier (data/tuning/).
## fight_service: the fight service charges it. The run's fight service
##   reports a lost attack's grid cost already multiplied by this option's
##   defeat_multiplier (service_result()), and the map applies every result's
##   cost as it is. With the shipped numbers this costs the same as
##   map_surcharge; what changes is who owns the rule, so a real fight service
##   can replace it (charge by damage taken, say) with no map change.
## no_surcharge: nobody adds anything; a lost attack costs what the fight
##   service reports, like a won one.


## Grid percent the map takes for a finished fight.
static func map_charge(kind: FightRequest.Kind, result: FightResult, v: CampaignVariants, defeat_multiplier: float) -> float:
	if kind == FightRequest.Kind.ATTACK and not result.is_victory() \
			and v.is_chosen(CampaignVariants.GRID_COST_OWNER, CampaignVariants.GRID_MAP_SURCHARGE):
		return result.grid_cost * defeat_multiplier
	return result.grid_cost


## The result a fight service reports under this decision: `result` itself,
## or for fight_service and a lost attack, a copy charging defeat_multiplier
## times the grid cost.
static func service_result(kind: FightRequest.Kind, result: FightResult, v: CampaignVariants) -> FightResult:
	if kind != FightRequest.Kind.ATTACK or result.is_victory() \
			or not v.is_chosen(CampaignVariants.GRID_COST_OWNER, CampaignVariants.GRID_FIGHT_SERVICE):
		return result
	var multiplier := v.param_float(CampaignVariants.GRID_COST_OWNER, "defeat_multiplier", 1.0)
	return FightResult.new(result.outcome, result.grid_cost * multiplier, result.rewards)
