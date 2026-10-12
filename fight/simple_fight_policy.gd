class_name SimpleFightPolicy
extends FightPolicy
## Uses the strongest single-target attack it can afford on the opponent with
## the least hp. Never heals, guards or hits all. Waits only when it can
## afford no attack at all (Strike costs energy under strike-cost "costs"):
## then it waits for its cheapest attack. Uses no randomness.


func choose(fight: Fight, actor: Combatant, _rng: RandomNumberGenerator) -> FightAction:
	var best: CombatSkill = null
	for skill in actor.skills():
		if skill.target == CombatSkill.TARGET_OPPONENT and actor.can_afford(skill) and (best == null or skill.power_percent > best.power_percent):
			best = skill
	var target: Combatant = null
	for c in fight.opponents_of(actor):
		if target == null or c.hp < target.hp:
			target = c
	if target == null:
		return null
	if best == null:
		return _wait_for_cheapest(actor)
	return FightAction.use(best.id, target.id)


func _wait_for_cheapest(actor: Combatant) -> FightAction:
	var cheapest: CombatSkill = null
	for skill in actor.skills():
		if skill.targets_opponents() and skill.energy_cost_milli() <= actor.max_energy_milli and (
				cheapest == null or skill.energy_cost < cheapest.energy_cost):
			cheapest = skill
	return FightAction.wait_for(cheapest.id) if cheapest != null else null
