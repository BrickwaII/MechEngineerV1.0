class_name DamagePipeline
extends RefCounted
## The one place a hit's damage is worked out: a fixed list of steps, each a
## modifier on the result of the one before. DamageRules, the intent planner,
## the preview and the battle screen's math lines all read it.
##
## STEPS, in order (the order is the rule; change it here only):
##   power       attack x power% x (100 + bonus% + slow bonus% + Stagger
##               bonus%) / 100 (the Stagger bonus while the target is
##               Staggered; StaggerRules)
##   defense     minus defense x defense% x (100 - pierce%) / 100
##   floor       / 100, at least min_damage
##   status      x (100 + the target's damage_taken_percent statuses)% (Exposed)
##   payoff      x (100 + payoff_bonus_percent)% when the target holds the
##               skill's payoff_condition
##   elasticity  the d-elasticity switch (ElasticityRules.reduce)
##   guard       the target's guard (DamageRules.guarded)
##   brace       minus what is left of the target's Brace (DamageRules.braced),
##               down to 0
##
## TODO(decision: status-stacking): status and payoff multiply, after the
## defense and floor (combat-rework-questions row 20).
##
## Without a status, payoff, Stagger, guard or Brace the result is exactly the pre-pipeline
## formula. With no target (stats only) the last steps read nothing.
## Whole numbers throughout; no randomness.

const STEPS: Array[String] = ["power", "defense", "floor", "status", "payoff", "elasticity", "guard", "brace"]


## The breakdown of `attacker` hitting `defender` with `skill`. `target` is the
## defending unit, for its statuses and guard; null leaves them out.
## `bonus_percent` is the turn's bonus (d-wait bonus_damage, weakest bonus).
@warning_ignore("integer_division")
static func run(attacker: UnitStats, defender: UnitStats, skill: CombatSkill, tuning: CombatTuning,
		bonus_percent := 0, target: Combatant = null) -> DamageBreakdown:
	var b := DamageBreakdown.new()
	b.attack = attacker.attack
	b.power_percent = skill.power_percent
	b.bonus_percent = bonus_percent
	b.speed_bonus_percent = SpeedRules.power_bonus_percent(attacker.speed, tuning)
	b.stagger_bonus_percent = DamageRules.stagger_bonus_percent(target, tuning) if target != null else 0
	b.defense = defender.defense
	b.defense_percent = tuning.defense_percent
	b.pierce_percent = clampi(skill.pierce_percent, 0, 100)
	b.min_damage = tuning.min_damage
	# power
	b.attack_term = b.attack * b.power_percent * (
		100 + b.bonus_percent + b.speed_bonus_percent + b.stagger_bonus_percent) / 100
	# defense
	b.defense_term = b.defense * b.defense_percent * (100 - b.pierce_percent) / 100
	b.raw = b.attack_term - b.defense_term
	# floor
	b.floored = maxi(b.min_damage, b.raw / 100)
	# status
	if target != null:
		for s in target.statuses:
			var def := tuning.statuses.get_status(s.status_id) if tuning.statuses != null else null
			if def != null and def.effect == StatusDef.EFFECT_DAMAGE_TAKEN_PERCENT:
				b.status_percent += def.amount * s.stacks
				b.status_ids.append(s.status_id)
	b.after_status = b.floored * (100 + b.status_percent) / 100 if b.status_percent != 0 else b.floored
	# payoff
	if target != null and skill.has_payoff() and target.has_status(skill.payoff_condition):
		b.payoff_percent = skill.payoff_bonus_percent
	b.after_payoff = b.after_status * (100 + b.payoff_percent) / 100 if b.payoff_percent != 0 else b.after_status
	# elasticity
	b.before_guard = ElasticityRules.reduce(b.after_payoff, defender, tuning)
	# guard
	b.guard_percent = target.guard_percent if target != null else 0
	b.after_guard = DamageRules.guarded(b.before_guard, b.guard_percent, tuning)
	# brace
	b.brace_absorb = target.brace_absorb if target != null else 0
	b.final = DamageRules.braced(b.after_guard, b.brace_absorb)
	b.absorbed = b.after_guard - b.final
	return b


## Every hit of `skill` from `attacker` on `target`, in order, as the fight
## would land them: each hit uses up the guard and the statuses a hit
## consumes, spends the Brace and strips plating (a hit that breaks it
## Staggers the target, so later hits get the Stagger bonus), and the hits
## stop once the target, or the attacker (from a guard's reflect), would be
## down. Reads only: the hits land on a copy.
static func hits(attacker: Combatant, target: Combatant, skill: CombatSkill, tuning: CombatTuning,
		bonus_percent := 0) -> Array[DamageBreakdown]:
	var out: Array[DamageBreakdown] = []
	var first := run(attacker.stats, target.stats, skill, tuning, bonus_percent, target)
	out.append(first)
	if skill.hit_count <= 1:
		return out
	var t := target.clone_for_preview()
	var manager := StatusManager.new(tuning.statuses)
	var attacker_hp := attacker.hp
	var b := first
	for i in range(1, skill.hit_count):
		t.hp = maxi(0, t.hp - b.final)
		@warning_ignore("integer_division")
		var back := maxi(0, b.before_guard - b.after_guard) * t.reflect_percent / 100 if t.guard_percent > 0 else 0
		attacker_hp -= back
		if not t.is_alive() or attacker_hp <= 0:
			break
		t.guard_percent = 0
		t.reflect_percent = 0
		t.brace_absorb -= b.absorbed
		manager.consume_after_hit(t, skill)
		if t.plating > 0 and tuning.stagger != null:
			t.plating -= mini(t.plating, tuning.stagger.pips_stripped(skill.damage_type, t.plating_weakness))
			t.staggered = t.staggered or t.plating == 0
		b = run(attacker.stats, t.stats, skill, tuning, bonus_percent, t)
		out.append(b)
	return out


## Total damage of every hit in `hits()`, before any cap at the target's hp.
static func total(attacker: Combatant, target: Combatant, skill: CombatSkill, tuning: CombatTuning,
		bonus_percent := 0) -> int:
	var sum := 0
	for b in hits(attacker, target, skill, tuning, bonus_percent):
		sum += b.final
	return sum
