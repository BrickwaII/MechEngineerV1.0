class_name CombatSkill
extends RefCounted
## One combat skill: a flat energy cost, a power multiplier, what it does and
## whom it may target. Plain data, read from data/combat/combat_tuning.json.
##
## Effects:
##   damage  hits an opponent (or, with target all_opponents, every living one)
##   heal    restores hp to a living ally (the user included)
##   guard   blocks power_percent of the next hit the target takes
## Targets:
##   opponent       one living opponent (the default for damage)
##   all_opponents  every living opponent; the action names any one of them
##   ally           one living unit on the user's side, the user included
##                  (the default for heal and guard)
##   self           the user only

const EFFECT_DAMAGE := "damage"
const EFFECT_HEAL := "heal"
const EFFECT_GUARD := "guard"
const EFFECTS: Array[String] = [EFFECT_DAMAGE, EFFECT_HEAL, EFFECT_GUARD]

const TARGET_OPPONENT := "opponent"
const TARGET_ALL_OPPONENTS := "all_opponents"
const TARGET_ALLY := "ally"
const TARGET_SELF := "self"
const TARGETS: Array[String] = [TARGET_OPPONENT, TARGET_ALL_OPPONENTS, TARGET_ALLY, TARGET_SELF]

var id: String
var display_name: String
## Whole energy points spent when the skill is used.
var energy_cost: int
## Damage before defense or hp restored, in percent of the user's attack; for
## a guard, the percent of the next hit blocked.
var power_percent: int
## One of EFFECTS.
var effect: String
## One of TARGETS.
var target: String
## The user's level in the skill. 1 for every skill not tied to a bot skill.
## With skill-progression = ranks this is the rank (SkillRanks).
var level := 1
## The effect step the battle screen draws, 1 to 10 (ui/fight SkillFx). The
## level itself with flat levels; with ranks, SkillRanks.fx_level().
var fx_level := 1
## True when display_name already names the rank ("Mega Strike +2"), so
## screens should not add a level of their own.
var names_rank := false
## Rank bonuses (data/combat/skill_ranks.json); 0 when the skill has none.
## Share of the target's defense a damage skill ignores, in percent.
var pierce_percent := 0
## An all-opponent skill's extra damage to the living opponent with least hp.
var weakest_bonus_percent := 0
## A heal also guards its target for this share of the next hit.
var heal_guard_percent := 0
## A guard also deals this share of the damage it blocks back to the attacker.
var reflect_percent := 0


func _init(
	p_id := "",
	p_display_name := "",
	p_energy_cost := 0,
	p_power_percent := 100,
	p_effect := EFFECT_DAMAGE,
	p_target := "",
) -> void:
	id = p_id
	display_name = p_display_name
	energy_cost = p_energy_cost
	power_percent = p_power_percent
	effect = p_effect
	target = p_target if not p_target.is_empty() else default_target(p_effect)


static func default_target(p_effect: String) -> String:
	return TARGET_OPPONENT if p_effect == EFFECT_DAMAGE else TARGET_ALLY


func is_heal() -> bool:
	return effect == EFFECT_HEAL


func is_guard() -> bool:
	return effect == EFFECT_GUARD


func is_damage() -> bool:
	return effect == EFFECT_DAMAGE


## True when the skill is aimed at an opponent rather than the user's side.
func targets_opponents() -> bool:
	return target == TARGET_OPPONENT or target == TARGET_ALL_OPPONENTS


func hits_all() -> bool:
	return target == TARGET_ALL_OPPONENTS


func energy_cost_milli() -> int:
	return energy_cost * Combatant.MILLI


## A copy as a unit with `p_level` in it holds it, named `p_name` ("" keeps the
## name). Every level above 1 adds `percent_per_level` percent of the power;
## a guard never blocks more than `max_guard_percent`. The cost does not change.
@warning_ignore("integer_division")
func at_level(p_level: int, p_name: String, percent_per_level: int, max_guard_percent: int) -> CombatSkill:
	var c := CombatSkill.new(
		id, p_name if not p_name.is_empty() else display_name, energy_cost, power_percent, effect, target)
	c.level = maxi(1, p_level)
	c.fx_level = c.level
	c.power_percent = power_percent * (100 + (c.level - 1) * percent_per_level) / 100
	if c.is_guard():
		c.power_percent = mini(c.power_percent, max_guard_percent)
	return c
