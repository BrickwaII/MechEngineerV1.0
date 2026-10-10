class_name IntentPlanner
extends RefCounted
## Decides what each enemy means to do, from the fight state and the unit's
## personality. Separate from combat resolution: it only reads the fight.
##
##   var planner := IntentPlanner.new()
##   var intents := planner.plan_all(fight)   # enemy id -> UnitIntent
##
## Every option a unit has is scored with IntentWeights, leaned by its
## Personality, and the highest score wins. Options, in a fixed order:
## - attack: each affordable attack skill on each living opponent (a skill that
##   hits all opponents is one option: its damage is the total, aimed at the
##   first; its kill bonus counts every opponent it would down);
## - heal: each affordable heal skill on each living, hurt ally (self included);
## - wait: for each attack skill it cannot afford yet but could, on each opponent.
## Ties go to the earlier option, so plans are deterministic. Damage counts the
## target's guard (Brace, Shield Ally) the way the fight resolves it. Guard
## skills are not planned: no enemy has one yet.
##
## How each scale leans the choice, with the default weights:
## - aggressive raises damage and kill, defensive raises the cost of energy;
## - supportive raises healing, solitary lowers it toward nothing;
## - reactive goes after the opponent that acted last, methodical after the
##   most worn-down one and is more willing to wait for a big skill.

var weights: IntentWeights
var personalities: EnemyPersonalities


func _init(p_weights: IntentWeights = null, p_personalities: EnemyPersonalities = null) -> void:
	weights = p_weights if p_weights != null else IntentWeights.load_default()
	personalities = p_personalities if p_personalities != null else EnemyPersonalities.load_default()


func personality_of(unit: Combatant) -> Personality:
	return personalities.for_unit(unit.id)


## Intent per living enemy, keyed by unit id, in roster order. Empty once the
## fight is over.
func plan_all(fight: Fight) -> Dictionary[String, UnitIntent]:
	var out: Dictionary[String, UnitIntent] = {}
	if fight.is_over():
		return out
	for unit in fight.living(Combatant.Side.ENEMY):
		var intent := plan(fight, unit)
		if intent != null:
			out[unit.id] = intent
	return out


## The best option for `unit`, or null when it has none.
func plan(fight: Fight, unit: Combatant) -> UnitIntent:
	var ranked := rank(fight, unit)
	return ranked[0] if not ranked.is_empty() else null


## Every option for `unit`, best first. Equal scores keep option order.
func rank(fight: Fight, unit: Combatant) -> Array[UnitIntent]:
	var options := options_for(fight, unit)
	var order := range(options.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		if options[a].score != options[b].score:
			return options[a].score > options[b].score
		return a < b)
	var out: Array[UnitIntent] = []
	for i: int in order:
		out.append(options[i])
	return out


## Every option for `unit`, scored, in option order.
func options_for(fight: Fight, unit: Combatant) -> Array[UnitIntent]:
	var out: Array[UnitIntent] = []
	if not unit.is_alive():
		return out
	var p := personality_of(unit)
	var opponents := fight.opponents_of(unit)
	var allies: Array[Combatant] = []
	allies.assign(fight.combatants.filter(func(c: Combatant) -> bool: return c.side == unit.side and c.is_alive()))
	var latest := latest_opponent_actor(fight, unit)
	for skill in unit.skills():
		var skill_id := skill.id
		if skill.is_guard():
			continue
		if skill.is_heal() or weights.role_of(skill_id) == IntentWeights.ROLE_HEAL:
			if unit.can_afford(skill):
				for ally in allies:
					var healed := heal_amount(unit, ally, skill)
					if healed > 0:
						var score := healed * weights.weight(IntentWeights.HEAL, p) - _cost_score(skill, p)
						out.append(UnitIntent.new(unit.id, UnitIntent.Kind.HEAL, FightAction.use(skill_id, ally.id), healed, score))
			continue
		var affordable := unit.can_afford(skill)
		if not affordable and skill.energy_cost_milli() > unit.max_energy_milli:
			continue
		var aims: Array[Combatant] = opponents
		if skill.hits_all() and not opponents.is_empty():
			aims = [opponents[0]]
		# The d-wait "bonus_damage" option: the turn that ends a wait hits harder.
		var bonus := WaitRules.damage_bonus_percent(unit.is_waiting() or not affordable, fight.tuning)
		for target in aims:
			var dmg := DamageRules.damage_to(unit, target, skill, fight.tuning, bonus)
			var score := _attack_score(dmg, target, target == latest, skill, p)
			if skill.hits_all():
				dmg = 0
				score = -_cost_score(skill, p)
				for o in opponents:
					var each := DamageRules.damage_to(unit, o, skill, fight.tuning, bonus)
					dmg += each
					score += _attack_score(each, o, o == latest, null, p)
			if affordable:
				out.append(UnitIntent.new(unit.id, UnitIntent.Kind.ATTACK, FightAction.use(skill_id, target.id), dmg, score))
			else:
				var action := FightAction.wait_for(skill_id)
				action.target_id = target.id
				score *= weights.weight(IntentWeights.WAIT, p)
				out.append(UnitIntent.new(unit.id, UnitIntent.Kind.WAIT, action, dmg, score))
	return out


## HP `skill` would restore to `ally`: attack x power% / 100, capped at what
## the ally has lost. The same rule the fight resolves heals with.
static func heal_amount(healer: Combatant, ally: Combatant, skill: CombatSkill) -> int:
	return DamageRules.heal(healer.stats, ally.hp, ally.max_hp, skill)


## The opponent of `unit` that took the most recent non-wait action, or null.
static func latest_opponent_actor(fight: Fight, unit: Combatant) -> Combatant:
	for i in range(fight.action_tags.size() - 1, -1, -1):
		var tag: String = fight.action_tags[i]
		var actor_id := tag.get_slice(":", 0)
		if tag.get_slice(":", 1) == "wait":
			continue
		var actor := fight.combatant(actor_id)
		if actor != null and actor.side != unit.side and actor.is_alive():
			return actor
	return null


## The score of dealing `dmg` to `target`; `skill`'s cost is subtracted unless null.
func _attack_score(dmg: int, target: Combatant, is_latest: bool, skill: CombatSkill, p: Personality) -> float:
	var score := dmg * weights.weight(IntentWeights.DAMAGE, p) - (_cost_score(skill, p) if skill != null else 0.0)
	if dmg >= target.hp:
		score += weights.weight(IntentWeights.KILL, p)
	if is_latest:
		score += weights.weight(IntentWeights.RETALIATE, p)
	if target.max_hp > 0:
		score += weights.weight(IntentWeights.FOCUS, p) * (1.0 - float(target.hp) / target.max_hp)
	return score


func _cost_score(skill: CombatSkill, p: Personality) -> float:
	return skill.energy_cost * weights.weight(IntentWeights.ENERGY_COST, p)
