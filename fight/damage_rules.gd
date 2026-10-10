class_name DamageRules
extends RefCounted
## Deterministic damage and healing: the same inputs always give the same
## number. There is no random dodge, no variance and no crits.
##
##   damage = max(min_damage, (attack x power% - defense x defense%) / 100)
##   heal   = min(attack x power% / 100, hp the target has lost)
##
## A guarded target takes max(min_damage, damage x (100 - guard%) / 100) from
## its next hit; see damage_to().


@warning_ignore("integer_division")
static func damage(attacker: UnitStats, defender: UnitStats, skill: CombatSkill, tuning: CombatTuning) -> int:
	var raw := attacker.attack * skill.power_percent - defender.defense * tuning.defense_percent
	var base := maxi(tuning.min_damage, raw / 100)
	return apply_elasticity(base, defender)


## Damage `attacker` deals `target` with `skill`, the target's guard included.
## Reads only; the fight clears the guard when the hit lands.
static func damage_to(attacker: Combatant, target: Combatant, skill: CombatSkill, tuning: CombatTuning) -> int:
	return guarded(damage(attacker.stats, target.stats, skill, tuning), target.guard_percent, tuning)


## `p_damage` after a guard blocking `guard_percent` of it.
@warning_ignore("integer_division")
static func guarded(p_damage: int, guard_percent: int, tuning: CombatTuning) -> int:
	if guard_percent <= 0:
		return p_damage
	return maxi(tuning.min_damage, p_damage * (100 - mini(100, guard_percent)) / 100)


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
