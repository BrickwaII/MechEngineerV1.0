class_name SmartFightPolicy
extends CarefulFightPolicy
## The harness's Scripted-smart squad policy (combat rework S8): the careful
## player (CarefulFightPolicy: answer wind-ups, cash in Exposed and Stagger,
## finish, break plating, set up Shred for a Heavy Strike, Wait to bank for
## Heavy Strike) with two more reads:
##  - Brace against any big telegraphed hit, not only a committed wind-up:
##    an enemy whose intent on screen aims at this bot for at least
##    brace_hp_percent of its HP (data/combat/smart_policy.json), when that
##    enemy acts before this bot's next turn. It first kills that enemy instead
##    when one affordable hit can.
##  - When no rule applies it takes the most real damage now
##    (GreedyFightPolicy), not the strongest power_percent.
## Reads only what the screen shows. Uses no randomness.

var tuning: SmartPolicyTuning


func _init(p_tuning: SmartPolicyTuning = null) -> void:
	tuning = p_tuning if p_tuning != null else SmartPolicyTuning.load_default()
	_greedy = GreedyFightPolicy.new()


func choose(fight: Fight, actor: Combatant, rng: RandomNumberGenerator) -> FightAction:
	var foes := fight.opponents_of(actor)
	if foes.is_empty():
		return null
	var answer := _answer_telegraph(fight, actor, foes)
	if answer != null:
		return answer
	var threat := big_threat(fight, actor)
	if threat != null:
		var kill := _finish(fight, actor, [threat] as Array[Combatant])
		if kill != null:
			return kill
		if actor.brace_absorb == 0 and _can(actor, BRACE):
			return FightAction.use(BRACE, actor.id)
	return super.choose(fight, actor, rng)


## The enemy whose telegraphed hit on `actor` is big (brace_hp_percent of its
## HP, or enough to down it) and lands before `actor` acts again; null if none.
func big_threat(fight: Fight, actor: Combatant) -> Combatant:
	var intents := fight.planner().plan_all(fight)
	var order := fight.upcoming(tuning.order_lookahead)
	var worst: Combatant = null
	var worst_amount := 0
	for foe in fight.opponents_of(actor):
		var intent: UnitIntent = intents.get(foe.id)
		if intent == null or intent.kind != UnitIntent.Kind.ATTACK or intent.target_id() != actor.id:
			continue
		if intent.amount * 100 < actor.hp * tuning.brace_hp_percent and intent.amount < actor.hp:
			continue
		if not _acts_before(order, foe.id, actor.id) or intent.amount <= worst_amount:
			continue
		worst = foe
		worst_amount = intent.amount
	return worst


## True when `first_id` takes a turn before `second_id`'s next one. The first
## entry is the unit deciding now, so it is skipped.
static func _acts_before(order: Array[TimelineEntry], first_id: String, second_id: String) -> bool:
	for i in range(1, order.size()):
		if order[i].combatant_id == first_id:
			return true
		if order[i].combatant_id == second_id:
			return false
	return false
