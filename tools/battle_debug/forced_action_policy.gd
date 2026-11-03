class_name ForcedActionPolicy
extends FightPolicy
## Plays a forced next action for a unit when the battle debugger (S9b) set
## one, else defers to `base`. A forced action is used once; one the fight
## refuses by the unit's turn (it can no longer afford it, its target is
## down) is dropped and `base` plays.

var base: FightPolicy
## Unit id -> the FightAction it plays on its next turn. Shared with the
## session, which sets and lists them.
var forced: Dictionary = {}
## Unit id -> why its forced action was dropped, for the session's log.
var dropped: Dictionary = {}


func _init(p_base: FightPolicy, p_forced: Dictionary) -> void:
	base = p_base
	forced = p_forced


func choose(fight: Fight, actor: Combatant, rng: RandomNumberGenerator) -> FightAction:
	if forced.has(actor.id):
		var action: FightAction = forced[actor.id]
		forced.erase(actor.id)
		var problem := fight.check_action(action)
		if problem.is_empty():
			return action.copy()
		dropped[actor.id] = problem
	return base.choose(fight, actor, rng) if base != null else null
