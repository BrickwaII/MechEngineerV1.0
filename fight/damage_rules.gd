class_name DamageRules
extends RefCounted
## Deterministic damage: the same inputs always give the same number. There is
## no random dodge, no variance and no crits.
##
##   damage = max(min_damage, (attack x power% - defense x defense%) / 100)


@warning_ignore("integer_division")
static func damage(attacker: UnitStats, defender: UnitStats, skill: CombatSkill, tuning: CombatTuning) -> int:
	var raw := attacker.attack * skill.power_percent - defender.defense * tuning.defense_percent
	var base := maxi(tuning.min_damage, raw / 100)
	return apply_elasticity(base, defender)


## TODO(decision: d-elasticity): what Elasticity does in combat is undecided.
## Placeholder: returns the damage unchanged. Elasticity has no effect yet.
static func apply_elasticity(p_damage: int, _defender: UnitStats) -> int:
	return p_damage
