class_name CarefulFightPolicy
extends FightPolicy
## A squad policy that uses the combat rework's verbs the way a careful
## player would, reading only what the screen shows (intents, plating,
## statuses, the turn order). A stand-in until S8's Smart policy; SimpleFightPolicy
## stays the greedy baseline. Uses no randomness. In order, the first that
## applies:
##  1. Answer a telegraphed hit (a committed wind-up): Shred the winder when
##     that breaks its plating (the Stagger cancels the hit); else, when the
##     hit is aimed at this bot, Brace.
##  2. Cash in: Heavy Strike (the payoff) on a Staggered or Exposed enemy.
##  3. Finish: the cheapest hit that downs an enemy.
##  4. Break plating: Shred (multi-hit) a plated enemy.
##  5. Set up: Shred the focus enemy when a bot that can Heavy Strike it acts
##     before the Exposed wears off (the enemy's own next action).
##  6. Bank: Wait for Heavy Strike when it is out of reach and Strike would
##     do less than half its damage (so spending now is worse than saving).
##  7. Otherwise the greedy choice (SimpleFightPolicy).
## Actions it lacks are skipped, so it plays any squad.

const SHRED := "shred"
const HEAVY := "heavy_strike"
const STRIKE := "strike"
const BRACE := "brace"
## How far ahead the turn order is read for a setup.
const ORDER_LOOKAHEAD := 8

## The fallback when no rule applies (rule 7). SmartFightPolicy swaps in
## GreedyFightPolicy.
var _greedy: FightPolicy = SimpleFightPolicy.new()


func choose(fight: Fight, actor: Combatant, rng: RandomNumberGenerator) -> FightAction:
	var foes := fight.opponents_of(actor)
	if foes.is_empty():
		return null
	var answer := _answer_telegraph(fight, actor, foes)
	if answer != null:
		return answer
	for foe in foes:
		if (foe.staggered or foe.has_status("exposed")) and _can(actor, HEAVY):
			return FightAction.use(HEAVY, foe.id)
	var finish := _finish(fight, actor, foes)
	if finish != null:
		return finish
	for foe in foes:
		if foe.plating > 0 and _can(actor, SHRED):
			return FightAction.use(SHRED, foe.id)
	var focus := _focus(foes)
	if _can(actor, SHRED) and not focus.has_status("exposed") and _payoff_before(fight, actor, focus):
		return FightAction.use(SHRED, focus.id)
	var bank := _bank(fight, actor, focus)
	if bank != null:
		return bank
	return _greedy.choose(fight, actor, rng)


func _can(actor: Combatant, skill_id: String) -> bool:
	return actor.has_skill(skill_id) and actor.can_afford(actor.skill(skill_id))


func _answer_telegraph(fight: Fight, actor: Combatant, foes: Array[Combatant]) -> FightAction:
	for foe in foes:
		if foe.committed == null:
			continue
		if foe.plating > 0 and _can(actor, SHRED):
			var shred := actor.skill(SHRED)
			var pips := fight.tuning.stagger.pips_stripped(shred.damage_type, foe.plating_weakness) * maxi(1, shred.hit_count)
			if foe.plating <= pips:
				return FightAction.use(SHRED, foe.id)
		if foe.committed.target_id() == actor.id and actor.brace_absorb == 0 and _can(actor, BRACE):
			return FightAction.use(BRACE, actor.id)
	return null


## The cheapest affordable single-target hit that downs a foe.
func _finish(fight: Fight, actor: Combatant, foes: Array[Combatant]) -> FightAction:
	var best: FightAction = null
	var best_cost := 1 << 30
	for skill in actor.skills():
		if skill.target != CombatSkill.TARGET_OPPONENT or not actor.can_afford(skill):
			continue
		for foe in foes:
			if damage(fight, actor, foe, skill) >= foe.hp and skill.energy_cost_milli() < best_cost:
				best = FightAction.use(skill.id, foe.id)
				best_cost = skill.energy_cost_milli()
	return best


## The foe the squad focuses: the least hp (as SimpleFightPolicy picks).
static func _focus(foes: Array[Combatant]) -> Combatant:
	var target: Combatant = null
	for c in foes:
		if target == null or c.hp < target.hp:
			target = c
	return target


## True when a squad bot holding Heavy Strike (this one included, after this
## action) takes a turn before `foe` acts again, so an Exposed put on now is
## cashed in before it wears off.
func _payoff_before(fight: Fight, actor: Combatant, foe: Combatant) -> bool:
	var order := fight.upcoming(ORDER_LOOKAHEAD)
	# The first entry is the actor itself, deciding now.
	for i in range(1, order.size()):
		var id := order[i].combatant_id
		if id == foe.id:
			return false
		var unit := fight.combatant(id)
		if unit == null or unit.side != actor.side or not unit.has_skill(HEAVY):
			continue
		var heavy := unit.skill(HEAVY)
		var energy := unit.energy_milli - (actor.skill(SHRED).energy_cost_milli() if unit == actor else 0)
		# Recharge before its turn is left out: a setup only when it is sure.
		if energy >= heavy.energy_cost_milli():
			return true
	return false


## Wait for Heavy Strike when it is out of reach now and Strike would do less
## than half its damage on the focus.
func _bank(fight: Fight, actor: Combatant, focus: Combatant) -> FightAction:
	if not actor.has_skill(HEAVY) or actor.is_waiting():
		return null
	var heavy := actor.skill(HEAVY)
	if actor.can_afford(heavy) or heavy.energy_cost_milli() > actor.max_energy_milli:
		return null
	var strike_damage := damage(fight, actor, focus, actor.skill(STRIKE)) if actor.has_skill(STRIKE) else 0
	if strike_damage * 2 >= damage(fight, actor, focus, heavy):
		return null
	return FightAction.wait_for(HEAVY)


## The damage `skill` would deal `target` now, every hit counted.
static func damage(fight: Fight, actor: Combatant, target: Combatant, skill: CombatSkill) -> int:
	if skill == null:
		return 0
	return DamagePipeline.run(actor.stats, target.stats, skill, fight.tuning, 0, target).final * maxi(1, skill.hit_count)
