class_name ScriptedFightPolicy
extends FightPolicy
## Plays a fixed list of actions in order, then hands over to `fallback`.
## An entry may be a FightAction or a Callable(fight, actor) -> FightAction.

var script_steps: Array
var fallback: FightPolicy
var _next := 0


func _init(p_steps: Array = [], p_fallback: FightPolicy = null) -> void:
	script_steps = p_steps
	fallback = p_fallback if p_fallback != null else SimpleFightPolicy.new()


func choose(fight: Fight, actor: Combatant, rng: RandomNumberGenerator) -> FightAction:
	if _next >= script_steps.size():
		return fallback.choose(fight, actor, rng)
	var step: Variant = script_steps[_next]
	_next += 1
	if step is Callable:
		return (step as Callable).call(fight, actor)
	return step
