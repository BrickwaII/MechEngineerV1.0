class_name DamageRules
extends RefCounted
## Deterministic damage and healing: the same inputs always give the same
## number. There is no random dodge, no variance and no crits. Damage is
## worked out by DamagePipeline (its STEPS list the order of every modifier);
## these are the entry points the fight and its readers call.
##
##   damage = max(min_damage, (attack x power% - defense x defense%) / 100)
##   heal   = min(attack x power% / 100, hp the target has lost)
##
## A skill with pierce_percent ignores that share of the defense term (a rank
## bonus, see SkillRanks).
## A guarded target takes max(min_damage, damage x (100 - guard%) / 100) from
## its next hit; a Bracing target then absorbs what is left of its Brace
## (down to 0 damage); see damage_to(). `bonus_percent` raises the raw damage (the
## d-wait "bonus_damage" option), and a slow attacker hits harder under the
## speed-range "compressed" option (SpeedRules); elasticity applies by the
## d-elasticity switch, see ElasticityRules. A target's statuses (Exposed) and
## a skill's payoff bonus raise the hit before elasticity and guard.


static func damage(attacker: UnitStats, defender: UnitStats, skill: CombatSkill, tuning: CombatTuning, bonus_percent := 0) -> int:
	return DamagePipeline.run(attacker, defender, skill, tuning, bonus_percent).final


## Damage `attacker` deals `target` with one hit of `skill`, the target's
## statuses (Exposed), the skill's payoff, the Stagger bonus (StaggerRules),
## the target's guard and then its Brace included. Reads only; the fight
## clears the guard, spends the Brace and used-up statuses when it lands.
static func damage_to(attacker: Combatant, target: Combatant, skill: CombatSkill, tuning: CombatTuning, bonus_percent := 0) -> int:
	return DamagePipeline.run(attacker.stats, target.stats, skill, tuning, bonus_percent, target).final


## damage_to() without the target's Brace: what the Brace has to absorb.
static func damage_before_brace(attacker: Combatant, target: Combatant, skill: CombatSkill, tuning: CombatTuning, bonus_percent := 0) -> int:
	return DamagePipeline.run(attacker.stats, target.stats, skill, tuning, bonus_percent, target).after_guard


## Damage of every hit of `skill` (hit_count) on `target`, summed, as the
## fight lands them: the first hit uses up the guard and Exposed, each hit
## spends the Brace and strips plating. Equal to damage_to() for a one-hit
## skill. Not capped at the target's hp.
static func action_damage_to(attacker: Combatant, target: Combatant, skill: CombatSkill, tuning: CombatTuning, bonus_percent := 0) -> int:
	return DamagePipeline.total(attacker, target, skill, tuning, bonus_percent)


## `p_damage` after a Brace with `absorb` left soaks it up; may reach 0.
static func braced(p_damage: int, absorb: int) -> int:
	return maxi(0, p_damage - maxi(0, absorb))


## Damage a Brace (an absorb skill) used by a unit with `user` stats absorbs:
## Defense x power% / 100.
@warning_ignore("integer_division")
static func brace_absorb(user: UnitStats, skill: CombatSkill) -> int:
	return maxi(0, user.defense * skill.power_percent / 100)


## Extra damage, in percent, every hit on `target` deals while it is Staggered.
static func stagger_bonus_percent(target: Combatant, tuning: CombatTuning) -> int:
	if tuning == null or tuning.stagger == null:
		return 0
	return tuning.stagger.bonus_against(target)


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
