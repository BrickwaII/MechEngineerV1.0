class_name DamageRules
extends RefCounted
## Deterministic damage and healing: the same inputs always give the same
## number. There is no random dodge, no variance and no crits.
##
##   damage = max(min_damage, (attack x power% - defense x defense%) / 100)
##   heal   = min(attack x power% / 100, hp the target has lost)


@warning_ignore("integer_division")
static func damage(attacker: UnitStats, defender: UnitStats, skill: CombatSkill, tuning: CombatTuning) -> int:
	var raw := attacker.attack * skill.power_percent - defender.defense * tuning.defense_percent
	var base := maxi(tuning.min_damage, raw / 100)
	return apply_elasticity(base, defender)


## TODO(decision: d-elasticity): what Elasticity does in combat is undecided.
## Placeholder: returns the damage unchanged. Elasticity has no effect yet.
static func apply_elasticity(p_damage: int, _defender: UnitStats) -> int:
	return p_damage


## Hp `skill` restores to `target` when `healer` uses it. Never more than the
## target has lost, never negative.
@warning_ignore("integer_division")
static func heal(healer: UnitStats, target_hp: int, target_max_hp: int, skill: CombatSkill) -> int:
	var power := maxi(0, healer.attack * skill.power_percent / 100)
	return mini(power, maxi(0, target_max_hp - target_hp))
