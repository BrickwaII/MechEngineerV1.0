extends RefCounted
## Builders and policies shared by the enemy archetype tests (combat rework
## S5): small fights against the shipped Charger, Plated and Scaler
## archetypes, played by a greedy policy and by one that answers the
## archetype's question.

const H := preload("res://tests/fight/fight_test_helpers.gd")

## The squad's kit in every archetype fight: the deep dive's minimal verbs.
const KIT: Array[String] = ["strike", "shred", "heavy_strike", "brace"]


## The default tuning, the squad fighting with KIT.
static func tuning() -> CombatTuning:
	var t := CombatTuning.load_default()
	t.player_skills.assign(KIT)
	return t


## An enemy definition shaped like enemy_tables.json, naming `archetype`
## ("" for none).
static func enemy(name: String, s: UnitStats, skills: Array, archetype := "") -> Dictionary:
	var d := H.enemy_def(name, s, skills)
	if not archetype.is_empty():
		d["archetype"] = archetype
	return d


## A fight of `allies` ({id: UnitStats}, in order) against `enemies` (enemy id
## -> definition), fielded in `order` (enemy ids, repeats allowed), with the
## shipped archetypes.
static func fight(allies: Dictionary, enemies: Dictionary, order: Array[String], p_tuning: CombatTuning = null,
		seed_value := 1) -> Fight:
	var levels := []
	for level in range(FightRequest.MIN_DEFENSE_LEVEL, FightRequest.MAX_DEFENSE_LEVEL + 1):
		levels.append({"level": level, "count": order.size(), "pool": [order[0]], "rewards": {"energy": 1, "material": 1}})
	var base := EnemyTable.from_dict({"enemies": enemies, "levels": levels})
	base.archetypes = EnemyArchetypeTable.load_default()
	var table := FixedEnemyTable.from_table(base, order)
	var squad: Array[SquadMemberSummary] = []
	for id: String in allies:
		squad.append(H.member(id, allies[id]))
	return Fight.new(H.request(squad), seed_value, p_tuning if p_tuning != null else tuning(), table)


## Plays `fight` to the end: the squad by `policy`, the enemies by their
## intents (IntentFightPolicy), as on screen. Returns the fight.
static func play(fight: Fight, policy: FightPolicy) -> Fight:
	var enemy_policy := IntentFightPolicy.new(fight.planner())
	var fallback := SimpleFightPolicy.new()
	var rng := HeadlessFightRunner.policy_rng(fight.fight_seed)
	var actor := fight.advance()
	while actor != null:
		HeadlessFightRunner.play_turn(
			fight, actor, policy if actor.side == Combatant.Side.PLAYER else enemy_policy, fallback, rng)
		actor = fight.advance()
	return fight


## Hp the squad lost over the fight.
static func squad_hp_lost(fight: Fight) -> int:
	var lost := 0
	for m in fight.request.squad:
		var c := fight.combatant(m.id)
		lost += m.hp - (c.hp if c != null else 0)
	return lost


static func won(fight: Fight) -> bool:
	return fight.outcome == FightResult.Outcome.VICTORY


## Every event of `kind` the fight raised, in order (listen before playing).
static func record(fight: Fight) -> Array[FightEvent]:
	var out: Array[FightEvent] = []
	fight.event_raised.connect(func(e: FightEvent) -> void: out.append(e))
	return out


static func of_kind(events: Array[FightEvent], kind: FightEvent.Kind) -> Array[FightEvent]:
	var out: Array[FightEvent] = []
	out.assign(events.filter(func(e: FightEvent) -> bool: return e.kind == kind))
	return out


## The policy that answers each archetype's question, reading the fight as a
## player would from the screen (intents, plating, Stagger, growth):
## 1. a Charger has committed a hit: Shred it when that breaks its plating
##    (the Stagger cancels the hit); else the bot it aims at Braces;
## 2. a Staggered enemy: Heavy Strike it (the Stagger bonus);
## 3. a plated enemy: Shred it, to break the plating;
## 4. a Scaler takes the strongest hit the bot can afford, before it grows;
## otherwise it plays as the greedy policy (SimpleFightPolicy) does, so the
## two differ only in the answers.
class AnswerPolicy:
	extends FightPolicy

	var _greedy := SimpleFightPolicy.new()

	func choose(fight: Fight, actor: Combatant, _rng: RandomNumberGenerator) -> FightAction:
		var foes := fight.opponents_of(actor)
		if foes.is_empty():
			return null
		var shred := actor.skill("shred")
		for foe in foes:
			if foe.committed == null:
				continue
			var pips := fight.tuning.stagger.pips_stripped(shred.damage_type, foe.plating_weakness) * shred.hit_count
			if foe.plating > 0 and foe.plating <= pips and actor.can_afford(shred):
				return FightAction.use("shred", foe.id)
			var brace := actor.skill("brace")
			if foe.committed.target_id() == actor.id and actor.brace_absorb == 0 and actor.can_afford(brace):
				return FightAction.use("brace", actor.id)
		for foe in foes:
			if foe.staggered and actor.can_afford(actor.skill("heavy_strike")):
				return FightAction.use("heavy_strike", foe.id)
		for foe in foes:
			if foe.plating > 0 and actor.can_afford(shred):
				return FightAction.use("shred", foe.id)
		for foe in foes:
			if foe.archetype != null and foe.archetype.scales():
				for skill_id in ["heavy_strike", "strike"]:
					if actor.can_afford(actor.skill(skill_id)):
						return FightAction.use(skill_id, foe.id)
		return _greedy.choose(fight, actor, _rng)


## Two allies, the squad every archetype fight fields.
static func allies() -> Dictionary:
	return {"rook": H.stats(40, 8, 4, 6, 10), "vale": H.stats(36, 7, 3, 7, 10)}


## A Charger (shipped archetype: strike, wind-up, Ram; three pips of plating)
## escorted by two weaker Grunts, which the greedy policy goes after first.
static func charger_fight(p_tuning: CombatTuning = null) -> Fight:
	return fight(allies(), {
		"charger": enemy("Charger", H.stats(60, 9, 3, 6, 10), ["strike", "ram"], "charger"),
		"grunt": enemy("Grunt", H.stats(18, 5, 2, 5, 6), ["strike"]),
	}, ["charger", "grunt", "grunt"] as Array[String], p_tuning)


## One Plated enemy (four pips) with a high Defense.
static func plated_fight(p_tuning: CombatTuning = null) -> Fight:
	return fight(allies(), {
		"plated": enemy("Plated", H.stats(70, 8, 5, 5, 10), ["strike", "heavy_strike"], "plated"),
	}, ["plated"] as Array[String], p_tuning)


## A Scaler (attack +20% of its base each action) with more hp than its two
## Grunt escorts, so the greedy policy leaves it to grow.
static func scaler_fight(p_tuning: CombatTuning = null) -> Fight:
	return fight(allies(), {
		"scaler": enemy("Scaler", H.stats(34, 7, 2, 6, 8), ["strike"], "scaler"),
		"grunt": enemy("Grunt", H.stats(20, 5, 2, 5, 6), ["strike"]),
	}, ["scaler", "grunt", "grunt"] as Array[String], p_tuning)
