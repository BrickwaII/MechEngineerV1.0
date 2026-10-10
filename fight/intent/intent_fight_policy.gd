class_name IntentFightPolicy
extends FightPolicy
## Plays a unit by its intent, so headless fights use the same choices the
## preview shows. When the best intent is one the fight cannot resolve (a heal
## skill the combat tuning does not mark as a heal), the next legal option is
## played instead. Uses no randomness.

var planner: IntentPlanner


func _init(p_planner: IntentPlanner = null) -> void:
	planner = p_planner if p_planner != null else IntentPlanner.new()


func choose(fight: Fight, actor: Combatant, _rng: RandomNumberGenerator) -> FightAction:
	for intent in planner.rank(fight, actor):
		if fight.check_action(intent.action).is_empty():
			return intent.action
	return null
