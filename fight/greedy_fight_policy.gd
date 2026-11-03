class_name GreedyFightPolicy
extends FightPolicy
## The deep dive's greedy bot (combat rework S8): every turn it takes the
## affordable action that takes the most HP off the opponents right now. Each
## damage action on each living opponent is tried on a FightCopy with the
## real rules, so hit counts, Exposed, payoff bonuses, Stagger, plating,
## guard, Brace and overkill all count (SimpleFightPolicy ranks by
## power_percent instead). Never Braces, heals, guards or sets up for later.
##
## Ties go to the cheaper action, then menu order, then roster order. When it
## can afford no damage action it waits for the cheapest one it can ever
## afford (Wait is free and always there). Uses no randomness.


func choose(fight: Fight, actor: Combatant, _rng: RandomNumberGenerator) -> FightAction:
	var foes := fight.opponents_of(actor)
	if foes.is_empty():
		return null
	var best: FightAction = null
	var best_damage := -1
	var best_cost := 0
	for skill in actor.skills():
		if not skill.is_damage() or not skill.targets_opponents() or not actor.can_afford(skill):
			continue
		# A hit-all action does the same whichever opponent it names.
		var targets: Array[Combatant] = [foes[0]] if skill.hits_all() else foes
		for foe in targets:
			var action := FightAction.use(skill.id, foe.id)
			var dealt := damage_of(fight, action)
			var cost := skill.energy_cost_milli()
			if dealt > best_damage or (dealt == best_damage and cost < best_cost):
				best = action
				best_damage = dealt
				best_cost = cost
	if best != null:
		return best
	return _wait_for_cheapest(actor)


## HP the pending unit's opponents would lose if it took `action` now: played
## on a FightCopy, so the live fight is never touched. -1 when refused.
static func damage_of(fight: Fight, action: FightAction) -> int:
	if not fight.check_action(action).is_empty():
		return -1
	var actor := fight.pending_actor
	var copy := FightCopy.of(fight)
	copy.submit(action)
	var lost := 0
	for c in fight.combatants:
		if c.side != actor.side:
			lost += c.hp - copy.combatant(c.id).hp
	return lost


func _wait_for_cheapest(actor: Combatant) -> FightAction:
	var cheapest: CombatSkill = null
	for skill in actor.skills():
		if skill.is_damage() and skill.targets_opponents() and skill.energy_cost_milli() <= actor.max_energy_milli and (
				cheapest == null or skill.energy_cost_milli() < cheapest.energy_cost_milli()):
			cheapest = skill
	return FightAction.wait_for(cheapest.id) if cheapest != null else null
