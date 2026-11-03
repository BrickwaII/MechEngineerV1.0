extends GdUnitTestSuite
## The Charger (combat rework S5): strike, then a telegraphed wind-up, then
## Ram. The wind-up commits the Ram and its target, holds until an ally has
## acted (the fairness rule), and a Stagger cancels it. The answer (Stagger it
## or Brace) beats greedy play.

const A := preload("res://tests/fight/archetypes/archetype_test_helpers.gd")

const CHARGER := "charger#1"


## Plays the fight until `unit_id` is the unit waiting for a decision: allies
## Strike the first living Grunt (else the Charger), enemies by intent.
static func _until_turn_of(fight: Fight, unit_id: String, max_decisions := 40) -> Combatant:
	var enemy_policy := IntentFightPolicy.new(fight.planner())
	var rng := HeadlessFightRunner.policy_rng(1)
	for i in max_decisions:
		var actor := fight.advance()
		if actor == null or actor.id == unit_id:
			return actor
		if actor.side == Combatant.Side.PLAYER:
			fight.submit(FightAction.use("strike", _first_grunt(fight)))
		else:
			HeadlessFightRunner.play_turn(fight, actor, enemy_policy, SimpleFightPolicy.new(), rng)
	return null


## Plays enemies by intent until an ally is waiting for a decision; returns it.
static func _next_ally(fight: Fight) -> Combatant:
	for i in 20:
		var actor := fight.advance()
		if actor == null or actor.side == Combatant.Side.PLAYER:
			return actor
		fight.submit(IntentFightPolicy.new(fight.planner()).choose(fight, actor, null))
	return null


static func _first_grunt(fight: Fight) -> String:
	for id in ["grunt#1", "grunt#2"]:
		var g := fight.combatant(id)
		if g != null and g.is_alive():
			return id
	return CHARGER


## Plays to the Charger's wind-up turn and winds up: returns the fight with
## the Ram committed.
static func _wound_up() -> Fight:
	var fight := A.charger_fight()
	var charger := _until_turn_of(fight, CHARGER)
	assert(charger != null)
	fight.submit(fight.planner().plan(fight, charger).action)  # strike
	charger = _until_turn_of(fight, CHARGER)
	var intent := fight.planner().plan(fight, charger)
	assert(intent.wind_up)
	fight.submit(intent.action)
	return fight


func test_the_charger_strikes_first_then_telegraphs_a_wind_up_of_ram() -> void:
	var fight := A.charger_fight()
	var charger := fight.combatant(CHARGER)
	assert_str(charger.intent.skill_id()).is_equal("strike")
	assert_int(charger.intent.kind).is_equal(UnitIntent.Kind.ATTACK)
	_until_turn_of(fight, CHARGER)
	fight.submit(fight.planner().plan(fight, charger).action)
	assert_int(charger.pattern_step).is_equal(1)
	assert_int(charger.intent.kind).is_equal(UnitIntent.Kind.WAIT)
	assert_bool(charger.intent.wind_up).is_true()
	assert_str(charger.intent.skill_id()).is_equal("ram")


func test_a_wind_up_commits_the_ram_and_its_target_and_announces_it() -> void:
	var fight := A.charger_fight()
	var charger := _until_turn_of(fight, CHARGER)
	fight.submit(fight.planner().plan(fight, charger).action)
	_until_turn_of(fight, CHARGER)
	var wind_up := fight.planner().plan(fight, charger)
	assert_str(fight.submit(wind_up.action)).is_empty()
	assert_bool(charger.is_waiting()).is_true()
	assert_object(charger.committed).is_not_null()
	assert_str(charger.committed.skill_id()).is_equal("ram")
	assert_str(charger.committed.target_id()).is_equal(wind_up.target_id())
	assert_int(charger.telegraph_wait).is_equal(1)
	var changed := A.of_kind(fight.last_events, FightEvent.Kind.INTENT_CHANGED)
	assert_int(changed.size()).is_equal(1)
	assert_str(changed[0].actor_id).is_equal(CHARGER)
	assert_str(changed[0].reason).is_equal("winds up")
	assert_str(changed[0].skill_id).is_equal("ram")
	assert_str(changed[0].target_id).is_equal(wind_up.target_id())
	assert_bool(changed[0].old_intent.wind_up).is_true()
	assert_int(changed[0].new_intent.kind).is_equal(UnitIntent.Kind.ATTACK)
	assert_bool(fight.log_text().contains("Charger winds up Ram")).is_true()
	# Committed: the planner offers nothing else, whatever the fight does.
	var ranked := fight.planner().rank(fight, charger)
	assert_int(ranked.size()).is_equal(1)
	assert_object(ranked[0]).is_same(charger.committed)


func test_the_wind_up_holds_until_an_ally_has_acted_even_with_the_energy() -> void:
	var fight := _wound_up()
	var charger := fight.combatant(CHARGER)
	charger.energy_milli = charger.max_energy_milli
	var allies_acted := 0
	for i in 10:
		var actor := fight.advance()
		if actor == charger:
			break
		if actor.side == Combatant.Side.PLAYER:
			allies_acted += 1
			fight.submit(FightAction.use("strike", _first_grunt(fight)))
		else:
			fight.submit(IntentFightPolicy.new(fight.planner()).choose(fight, actor, null))
	assert_object(fight.pending_actor).is_same(charger)
	assert_int(allies_acted).is_greater_equal(1)
	assert_int(charger.telegraph_wait).is_equal(0)
	var action := IntentFightPolicy.new(fight.planner()).choose(fight, charger, null)
	assert_str(action.skill_id).is_equal("ram")
	assert_str(action.target_id).is_equal(charger.committed.target_id())
	assert_str(fight.submit(action)).is_empty()
	assert_object(charger.committed).is_null()
	assert_int(charger.pattern_step).is_equal(3)
	assert_str(charger.intent.skill_id()).is_equal("strike")


func test_a_wind_up_without_a_telegraph_ends_like_a_plain_wait() -> void:
	for telegraph in [0, 1]:
		var fight := A.charger_fight()
		var charger := fight.combatant(CHARGER)
		charger.archetype = EnemyArchetype.from_dict("charger", {
			"name": "Charger", "plating": 3, "intent_pattern": ["wind_up", "ram"], "wind_up_opponent_actions": telegraph})
		_until_turn_of(fight, CHARGER)
		charger.energy_milli = charger.max_energy_milli
		fight.submit(fight.planner().plan(fight, charger).action)
		assert_int(charger.telegraph_wait).is_equal(telegraph)
		charger.tick()
		# Affordable and a tick in: only the telegraph holds it.
		assert_bool(charger.is_ready(fight.timeline.threshold)).is_equal(telegraph == 0)


func test_a_stagger_cancels_the_committed_ram_and_starts_the_pattern_over() -> void:
	var fight := _wound_up()
	var charger := fight.combatant(CHARGER)
	charger.plating = 1
	assert_object(_next_ally(fight)).is_not_null()
	assert_str(fight.submit(FightAction.use("strike", CHARGER))).is_empty()
	assert_bool(charger.staggered).is_true()
	assert_bool(charger.is_waiting()).is_false()
	assert_object(charger.committed).is_null()
	assert_object(charger.intent).is_null()
	assert_int(charger.pattern_step).is_equal(0)
	var changed := A.of_kind(fight.last_events, FightEvent.Kind.INTENT_CHANGED)
	assert_int(changed.size()).is_equal(1)
	assert_str(changed[0].reason).is_equal("staggered")
	assert_str(changed[0].old_intent.skill_id()).is_equal("ram")
	assert_object(changed[0].new_intent).is_null()
	# Its next turn is lost to recovering; then it plans its first step again.
	var events := A.record(fight)
	while charger.staggered:
		var actor := fight.advance()
		fight.submit(FightAction.use("strike", _first_grunt(fight)) if actor.side == Combatant.Side.PLAYER
			else IntentFightPolicy.new(fight.planner()).choose(fight, actor, null))
	var recovered := A.of_kind(events, FightEvent.Kind.INTENT_CHANGED).filter(
		func(e: FightEvent) -> bool: return e.actor_id == CHARGER and e.reason == "recovered")
	assert_int(recovered.size()).is_equal(1)
	assert_str(recovered[0].new_intent.skill_id()).is_equal("strike")
	assert_bool(A.of_kind(events, FightEvent.Kind.HIT).any(
		func(e: FightEvent) -> bool: return e.skill_id == "ram")).is_false()


func test_the_committed_ram_re_aims_when_its_target_goes_down() -> void:
	var fight := _wound_up()
	var charger := fight.combatant(CHARGER)
	var first := charger.committed.target_id()
	var other := "vale" if first == "rook" else "rook"
	fight.combatant(first).hp = 0
	var events := A.record(fight)
	var ally := _next_ally(fight)
	assert_str(ally.id).is_equal(other)
	fight.submit(FightAction.use("strike", _first_grunt(fight)))
	assert_str(charger.committed.skill_id()).is_equal("ram")
	assert_str(charger.committed.target_id()).is_equal(other)
	var changed := A.of_kind(events, FightEvent.Kind.INTENT_CHANGED).filter(
		func(e: FightEvent) -> bool: return e.actor_id == CHARGER)
	assert_int(changed.size()).is_equal(1)
	assert_str(changed[0].reason).is_equal("target down")
	assert_str(changed[0].target_id).is_equal(other)


## The fairness rule over whole fights: every Ram that lands was announced
## (INTENT_CHANGED "winds up") with at least one ally decision in between.
func test_every_ram_is_telegraphed_at_least_one_ally_action_ahead() -> void:
	var rams := 0
	for policy: FightPolicy in [SimpleFightPolicy.new(), PatientFightPolicy.new()]:
		var fight := A.charger_fight()
		var events := A.record(fight)
		A.play(fight, policy)
		var announced_at := -1
		var allies_since := 0
		for e in events:
			if e.kind == FightEvent.Kind.INTENT_CHANGED and e.reason == "winds up":
				announced_at = e.action_index
				allies_since = 0
			elif e.kind in [FightEvent.Kind.SKILL, FightEvent.Kind.WAIT] and e.actor_id in ["rook", "vale"]:
				allies_since += 1
			elif e.kind == FightEvent.Kind.SKILL and e.skill_id == "ram":
				rams += 1
				assert_int(announced_at).is_greater_equal(0)
				assert_int(allies_since).is_greater_equal(1)
				announced_at = -1
	assert_int(rams).is_greater(0)


func test_answering_the_charger_beats_greedy_play() -> void:
	var greedy := A.play(A.charger_fight(), SimpleFightPolicy.new())
	var answer_fight := A.charger_fight()
	var events := A.record(answer_fight)
	var answer := A.play(answer_fight, A.AnswerPolicy.new())
	assert_bool(A.won(answer)).is_true()
	assert_int(A.squad_hp_lost(answer)).is_less(A.squad_hp_lost(greedy))
	# Greedy lets the Ram land; the answer Staggers the Charger instead.
	assert_bool(greedy.log_text().contains("Charger uses Ram")).is_true()
	assert_bool(answer.log_text().contains("Charger uses Ram")).is_false()
	assert_int(A.of_kind(events, FightEvent.Kind.STAGGER).size()).is_greater(0)


func test_charger_fights_replay_exactly() -> void:
	var a := A.play(A.charger_fight(), A.AnswerPolicy.new())
	var b := A.play(A.charger_fight(), A.AnswerPolicy.new())
	assert_str(a.log_text()).is_equal(b.log_text())
