class_name SimpleFightPolicy
extends FightPolicy
## Uses the strongest skill it can afford on the opponent with the least hp.
## Never waits. Uses no randomness.


func choose(fight: Fight, actor: Combatant, _rng: RandomNumberGenerator) -> FightAction:
	var best: CombatSkill = null
	for id in actor.skill_ids:
		var skill := fight.tuning.skill(id)
		if skill != null and actor.can_afford(skill) and (best == null or skill.power_percent > best.power_percent):
			best = skill
	var target: Combatant = null
	for c in fight.opponents_of(actor):
		if target == null or c.hp < target.hp:
			target = c
	if best == null or target == null:
		return null
	return FightAction.use(best.id, target.id)
