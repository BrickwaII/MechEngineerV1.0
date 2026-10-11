class_name DamageRules
extends RefCounted
## Deterministic damage and healing: the same inputs always give the same
## number. There is no random dodge, no variance and no crits.
##
##   damage = max(min_damage, (attack x power% - defense x defense%) / 100)
##   heal   = min(attack x power% / 100, hp the target has lost)
##
## A skill with pierce_percent ignores that share of the defense term (a rank
## bonus, see SkillRanks).
## A guarded target takes max(min_damage, damage x (100 - guard%) / 100) from
## its next hit; see damage_to(). `bonus_percent` raises the raw damage (the
## d-wait "bonus_damage" option); elasticity applies by the d-elasticity
## switch, see ElasticityRules.


@warning_ignore("integer_division")
static func damage(attacker: UnitStats, defender: UnitStats, skill: CombatSkill, tuning: CombatTuning, bonus_percent := 0) -> int:
	var raw := (attacker.attack * skill.power_percent * (100 + bonus_percent) / 100
		- defender.defense * tuning.defense_percent * (100 - clampi(skill.pierce_percent, 0, 100)) / 100)
	var base := maxi(tuning.min_damage, raw / 100)
	return apply_elasticity(base, defender, tuning)


## Damage `attacker` deals `target` with `skill`, the target's guard included.
## Reads only; the fight clears the guard when the hit lands.
static func damage_to(attacker: Combatant, target: Combatant, skill: CombatSkill, tuning: CombatTuning, bonus_percent := 0) -> int:
	return guarded(damage(attacker.stats, target.stats, skill, tuning, bonus_percent), target.guard_percent, tuning)


## `p_damage` after a guard blocking `guard_percent` of it.
@warning_ignore("integer_division")
static func guarded(p_damage: int, guard_percent: int, tuning: CombatTuning) -> int:
	if guard_percent <= 0:
		return p_damage
	return maxi(tuning.min_damage, p_damage * (100 - mini(100, guard_percent)) / 100)


## TODO(decision: d-elasticity): what Elasticity does in combat is undecided.
## Default ("none"), and with no tuning: the damage unchanged. The options
## live in ElasticityRules.
static func apply_elasticity(p_damage: int, defender: UnitStats, tuning: CombatTuning = null) -> int:
	return ElasticityRules.reduce(p_damage, defender, tuning)


## Hp `skill` restores to `target` when `healer` uses it. Never more than the
## target has lost, never negative.
@warning_ignore("integer_division")
static func heal(healer: UnitStats, target_hp: int, target_max_hp: int, skill: CombatSkill) -> int:
	var power := maxi(0, healer.attack * skill.power_percent / 100)
	return mini(power, maxi(0, target_max_hp - target_hp))


## The living unit in `units` with the least hp; the earlier one wins a tie.
## A rank bonus (weakest_bonus_percent) hits it harder.
static func weakest(units: Array[Combatant]) -> Combatant:
	var best: Combatant = null
	for u in units:
		if u.is_alive() and (best == null or u.hp < best.hp):
			best = u
	return best
