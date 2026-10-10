class_name ElasticityRules
extends RefCounted
## What Elasticity does in combat, by the d-elasticity switch (FightVariants):
##   none              nothing (the default)
##   reduce_big_hits   the part of a hit above big_hit_percent of the
##                     defender's max hp is cut by elasticity x
##                     reduce_percent_per_point percent, at most
##                     max_reduce_percent
##   resist_knockback  every damaging hit knocks the target's gauge back by
##                     knockback_gauge less elasticity x resist_gauge_per_point
##   energy_when_hit   a unit that takes damage regains elasticity x
##                     energy_milli_per_point thousandths of energy
## Every rule is deterministic and whole-number.


## `p_damage` after the defender's elasticity, before any guard.
@warning_ignore("integer_division")
static func reduce(p_damage: int, defender: UnitStats, tuning: CombatTuning) -> int:
	if tuning == null or not tuning.variants.is_chosen(FightVariants.ELASTICITY, FightVariants.ELASTICITY_BIG_HITS):
		return p_damage
	var v := tuning.variants
	var big := maxi(0, defender.hp) * v.param_int(FightVariants.ELASTICITY, "big_hit_percent") / 100
	if p_damage <= big:
		return p_damage
	var cut := clampi(
		maxi(0, defender.elasticity) * v.param_int(FightVariants.ELASTICITY, "reduce_percent_per_point"),
		0, clampi(v.param_int(FightVariants.ELASTICITY, "max_reduce_percent"), 0, 100))
	return maxi(tuning.min_damage, big + (p_damage - big) * (100 - cut) / 100)


## Gauge a damaging hit takes off `target`.
static func knockback(target: UnitStats, tuning: CombatTuning) -> int:
	if not tuning.variants.is_chosen(FightVariants.ELASTICITY, FightVariants.ELASTICITY_KNOCKBACK):
		return 0
	var v := tuning.variants
	return maxi(0, v.param_int(FightVariants.ELASTICITY, "knockback_gauge")
		- maxi(0, target.elasticity) * v.param_int(FightVariants.ELASTICITY, "resist_gauge_per_point"))


## Energy, in thousandths, a unit regains when it takes damage.
static func energy_when_hit_milli(target: UnitStats, tuning: CombatTuning) -> int:
	if not tuning.variants.is_chosen(FightVariants.ELASTICITY, FightVariants.ELASTICITY_ENERGY):
		return 0
	return maxi(0, target.elasticity) * maxi(0, tuning.variants.param_int(FightVariants.ELASTICITY, "energy_milli_per_point"))


## Applies the after-hit rules to `target`, which just took `p_damage`.
static func after_hit(target: Combatant, p_damage: int, tuning: CombatTuning) -> void:
	if p_damage <= 0 or not target.is_alive():
		return
	target.gauge = maxi(0, target.gauge - knockback(target.stats, tuning))
	target.energy_milli = mini(target.max_energy_milli, target.energy_milli + energy_when_hit_milli(target.stats, tuning))
