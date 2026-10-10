class_name RandomFightPolicy
extends FightPolicy
## Picks uniformly, with the given rng, among every legal action: each affordable
## damage skill on each living opponent, plus waiting for each skill it cannot
## afford yet. Heal and guard skills are left out.
## For tests and simulation; replays exactly from the rng's seed.


func choose(fight: Fight, actor: Combatant, rng: RandomNumberGenerator) -> FightAction:
	var options: Array[FightAction] = []
	for skill in actor.skills():
		var id := skill.id
		if not skill.is_damage():
			continue
		if actor.can_afford(skill):
			for target in fight.opponents_of(actor):
				options.append(FightAction.use(id, target.id))
		elif skill.energy_cost_milli() <= actor.max_energy_milli:
			options.append(FightAction.wait_for(id))
	if options.is_empty():
		return null
	return options[rng.randi_range(0, options.size() - 1)]
