class_name PatientFightPolicy
extends FightPolicy
## Like SimpleFightPolicy, but saves up: when its strongest attack costs more
## energy than it has (and no more than its pool), it waits for that attack
## instead of using a weaker one. Uses no randomness.
##
## Exists so batch runs exercise waiting: IntentFightPolicy almost never
## waits with today's weights, so the d-wait options would all look the same.
## With the d-wait-length "exact" variant it names the exact ticks it needs,
## which ends on the same tick a snapping wait would.


func choose(fight: Fight, actor: Combatant, _rng: RandomNumberGenerator) -> FightAction:
	var best_now: CombatSkill = null
	var best_ever: CombatSkill = null
	for skill in actor.skills():
		if not skill.targets_opponents() or skill.energy_cost_milli() > actor.max_energy_milli:
			continue
		if best_ever == null or skill.power_percent > best_ever.power_percent:
			best_ever = skill
		if actor.can_afford(skill) and (best_now == null or skill.power_percent > best_now.power_percent):
			best_now = skill
	if best_ever != null and not actor.can_afford(best_ever) and not actor.is_waiting():
		return _wait(fight, actor, best_ever)
	var target: Combatant = null
	for c in fight.opponents_of(actor):
		if target == null or c.hp < target.hp:
			target = c
	if best_now == null or target == null:
		return null
	return FightAction.use(best_now.id, target.id)


func _wait(fight: Fight, actor: Combatant, skill: CombatSkill) -> FightAction:
	if not WaitRules.exact_waits_allowed(fight.tuning):
		return FightAction.wait_for(skill.id)
	var missing := skill.energy_cost_milli() - actor.energy_milli - WaitRules.start_bonus_milli(fight.tuning)
	var ticks := ceili(float(maxi(0, missing)) / maxi(1, actor.wait_recharge_milli))
	return FightAction.wait_exact(skill.id, clampi(ticks, 1, WaitRules.max_wait_ticks(fight.tuning)))
