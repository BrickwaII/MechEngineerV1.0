class_name CombatSkill
extends RefCounted
## One combat skill: a flat energy cost, a power multiplier, what it does and
## whom it may target. Plain data, read from data/combat/actions.json by
## ActionTable. This is the combat rework plan's ActionDef
## (docs/combat-rework-map.md, S1): the class keeps its name so every reader
## of skills keeps working.
##
## The rework fields (recovery, hit_count, damage_type, tags, applies_status,
## payoff_condition, payoff_bonus_percent) default to what every action did
## before them. Fights read hit_count, applies_status and the payoff (S3:
## Fight, DamagePipeline); S2 (recovery), S6 (tags) and S13 (damage types)
## give the others meaning.
##
## Effects:
##   damage  hits an opponent (or, with target all_opponents, every living one)
##   heal    restores hp to a living ally (the user included)
##   guard   blocks power_percent of the next hit the target takes
##   absorb  Brace: the target absorbs up to power_percent of the user's
##           Defense in damage, across every hit, until the target's next
##           action (DamageRules.brace_absorb)
## Targets:
##   opponent       one living opponent (the default for damage)
##   all_opponents  every living opponent; the action names any one of them
##   ally           one living unit on the user's side, the user included
##                  (the default for heal and guard)
##   self           the user only

const EFFECT_DAMAGE := "damage"
const EFFECT_HEAL := "heal"
const EFFECT_GUARD := "guard"
const EFFECT_ABSORB := "absorb"
const EFFECTS: Array[String] = [EFFECT_DAMAGE, EFFECT_HEAL, EFFECT_GUARD, EFFECT_ABSORB]

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
## a guard, the percent of the next hit blocked; for an absorb, the percent
## of the user's Defense absorbed.
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

## Rework definition fields (S1). See the class comment for which fights read.
## How far the user is pushed back after acting, on top of the turn
## threshold, in percent of a turn (action_threshold units: 100 is one whole
## turn, scaled by TimelineOps.turn_gauge()). 0: no extra cost in time. Read
## by fights since S2.
var recovery := 0
## Hits a damage action lands per use; power_percent is the damage of each. (S3)
var hit_count := 1
## The action's damage type; "" is untyped. Only damage actions have one. (S13)
var damage_type := ""
## Free-form labels the action tagger and drift rules read (offense, setup,
## payoff, ...). (S6)
var tags: Array[String] = []
## A status id (data/combat/statuses.json) the action puts on its target; ""
## puts none. (S3)
var applies_status := ""
## A status id the target must hold for the payoff bonus; "" has no payoff. (S3)
var payoff_condition := ""
## Extra damage, in percent, against a target that meets payoff_condition. (S3)
var payoff_bonus_percent := 0


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


## Brace: absorbs damage until the target's next action.
func is_absorb() -> bool:
	return effect == EFFECT_ABSORB


func is_damage() -> bool:
	return effect == EFFECT_DAMAGE


## True when the skill is aimed at an opponent rather than the user's side.
func targets_opponents() -> bool:
	return target == TARGET_OPPONENT or target == TARGET_ALL_OPPONENTS


func hits_all() -> bool:
	return target == TARGET_ALL_OPPONENTS


func energy_cost_milli() -> int:
	return energy_cost * Combatant.MILLI


## True when the action names a payoff: a status that adds damage.
func has_payoff() -> bool:
	return not payoff_condition.is_empty()


## The action defined by one entry of data/combat/actions.json. Keys left out
## take the defaults above.
static func from_dict(p_id: String, d: Dictionary) -> CombatSkill:
	var c := CombatSkill.new(
		p_id, String(d.get("name", p_id)), int(d.get("energy_cost", 0)), int(d.get("power_percent", 100)),
		String(d.get("effect", EFFECT_DAMAGE)), String(d.get("target", "")))
	c.recovery = int(d.get("recovery", 0))
	c.hit_count = int(d.get("hit_count", 1))
	c.damage_type = String(d.get("damage_type", ""))
	for tag: Variant in d.get("tags", []):
		c.tags.append(String(tag))
	c.applies_status = String(d.get("applies_status", ""))
	c.payoff_condition = String(d.get("payoff_condition", ""))
	c.payoff_bonus_percent = int(d.get("payoff_bonus_percent", 0))
	return c


## Problems with this action's definition; empty when usable. `status_ids`
## are the statuses it may name; null skips that check.
func validate(status_ids: Variant = null) -> Array[String]:
	var problems: Array[String] = []
	if id.is_empty():
		problems.append("an action has no id")
	if not effect in EFFECTS:
		problems.append("action %s has unknown effect %s" % [id, effect])
	if not target in TARGETS:
		problems.append("action %s has unknown target %s" % [id, target])
	elif effect in EFFECTS and is_damage() != targets_opponents():
		problems.append("action %s: damage actions target opponents, others their own side" % id)
	if energy_cost < 0:
		problems.append("action %s energy_cost may not be negative" % id)
	if power_percent < 0:
		problems.append("action %s power_percent may not be negative" % id)
	if recovery < 0:
		problems.append("action %s recovery may not be negative" % id)
	if hit_count < 1:
		problems.append("action %s hit_count must be at least 1" % id)
	elif hit_count > 1 and not is_damage():
		problems.append("action %s: only damage actions hit more than once" % id)
	if not damage_type.is_empty() and not is_damage():
		problems.append("action %s: only damage actions have a damage type" % id)
	var seen := {}
	for tag in tags:
		if tag.is_empty():
			problems.append("action %s has an empty tag" % id)
		elif seen.has(tag):
			problems.append("action %s lists tag %s twice" % [id, tag])
		elif not tag in ActionTag.TAGS:
			problems.append("action %s has unknown tag %s (not an ActionTag tag)" % [id, tag])
		seen[tag] = true
	if has_payoff():
		if not is_damage():
			problems.append("action %s: only damage actions have a payoff" % id)
		if payoff_bonus_percent <= 0:
			problems.append("action %s payoff needs a payoff_bonus_percent above 0" % id)
	elif payoff_bonus_percent != 0:
		problems.append("action %s has a payoff_bonus_percent but no payoff_condition" % id)
	if status_ids != null:
		if not applies_status.is_empty() and not applies_status in status_ids:
			problems.append("action %s applies unknown status %s" % [id, applies_status])
		if has_payoff() and not payoff_condition in status_ids:
			problems.append("action %s payoff names unknown status %s" % [id, payoff_condition])
	return problems


## A fresh copy of the definition named `p_name` ("" keeps the name): every
## data field, but level 1 and none of the rank bonuses or rank naming.
func copy_definition(p_name := "") -> CombatSkill:
	var c := CombatSkill.new(
		id, p_name if not p_name.is_empty() else display_name, energy_cost, power_percent, effect, target)
	c.recovery = recovery
	c.hit_count = hit_count
	c.damage_type = damage_type
	c.tags = tags.duplicate()
	c.applies_status = applies_status
	c.payoff_condition = payoff_condition
	c.payoff_bonus_percent = payoff_bonus_percent
	return c


## A copy as a unit with `p_level` in it holds it, named `p_name` ("" keeps the
## name). Every level above 1 adds `percent_per_level` percent of the power;
## a guard never blocks more than `max_guard_percent`. The cost does not change.
@warning_ignore("integer_division")
func at_level(p_level: int, p_name: String, percent_per_level: int, max_guard_percent: int) -> CombatSkill:
	var c := copy_definition(p_name)
	c.level = maxi(1, p_level)
	c.fx_level = c.level
	c.power_percent = power_percent * (100 + (c.level - 1) * percent_per_level) / 100
	if c.is_guard():
		c.power_percent = mini(c.power_percent, max_guard_percent)
	return c
