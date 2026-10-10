class_name FightPolicy
extends RefCounted
## Picks an action for the unit whose turn it is. Extend it and override choose().
## Must decide from the fight state and `rng` only, so fights replay from a seed.


func choose(_fight: Fight, _actor: Combatant, _rng: RandomNumberGenerator) -> FightAction:
	push_error("%s does not override FightPolicy.choose()" % get_script().resource_path)
	return null
