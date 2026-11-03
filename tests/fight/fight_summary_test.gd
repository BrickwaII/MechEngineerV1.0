extends GdUnitTestSuite
## The fight summary (combat rework S6): what a fight came to, tallied from
## its one log. Checked against the log, the units and the result it reads.

const A := preload("res://tests/fight/archetypes/archetype_test_helpers.gd")
const T := preload("res://tests/fight/intent/intent_test_helpers.gd")


static func _answered_fight() -> Fight:
	return A.play(A.charger_fight(), A.AnswerPolicy.new())


## Allies "a" and "b" (fast, big batteries) against one slow, sturdy foe.
static func _kit_fight() -> Fight:
	var tuning := CombatTuning.load_default()
	tuning.player_skills.assign(["strike", "shred", "heavy_strike", "brace"])
	var ally := T.stats(60, 12, 3, 11, 20)
	return T.fight(
		[{"id": "a", "stats": ally}, {"id": "b", "stats": ally}],
		[{"id": "foe#1", "stats": T.stats(400, 6, 4, 3, 10), "skills": ["strike"]}], tuning)


func _decide(fight: Fight, actor_id: String, action: FightAction) -> void:
	assert_str(fight.advance().id).is_equal(actor_id)
	assert_str(fight.submit(action)).is_empty()


func test_a_short_fight_counts_uses_tags_setups_and_combos() -> void:
	var fight := _kit_fight()
	_decide(fight, "a", FightAction.use("shred", "foe#1"))
	_decide(fight, "b", FightAction.use("heavy_strike", "foe#1"))
	var s := fight.summary()
	assert_int(s.decisions).is_equal(2)
	assert_int(s.squad.decisions).is_equal(2)
	assert_dict(s.squad.action_uses).is_equal({"shred": 1, "heavy_strike": 1})
	assert_dict(s.squad.tag_uses).is_equal({"offense": 2, "setup": 1, "payoff": 1})
	assert_int(s.squad.setups).is_equal(1)
	assert_int(s.squad.combos).is_equal(1)
	assert_dict(s.squad.statuses_applied).is_equal({"exposed": 1})
	assert_int(s.unit("a").setups).is_equal(1)
	assert_int(s.unit("a").combos).is_equal(0)
	assert_int(s.unit("b").combos).is_equal(1)
	assert_int(s.enemies.decisions).is_equal(0)
	assert_int(s.squad.tag_percent("offense")).is_equal(100)
	assert_int(s.squad.share_percent("shred")).is_equal(50)


func test_hp_is_worked_back_from_the_log() -> void:
	var fight := _kit_fight()
	var foe := fight.combatant("foe#1")
	var start := foe.hp
	_decide(fight, "a", FightAction.use("shred", "foe#1"))
	_decide(fight, "b", FightAction.use("heavy_strike", "foe#1"))
	var t := fight.summary().unit("foe#1")
	assert_int(t.hp_start).is_equal(start)
	assert_int(t.hp_end).is_equal(foe.hp)
	assert_int(t.hp_lost()).is_equal(start - foe.hp)
	assert_int(t.damage_taken).is_equal(start - foe.hp)
	assert_int(fight.summary().squad.damage_dealt).is_equal(start - foe.hp)


func test_a_wait_counts_as_a_banked_decision() -> void:
	var fight := _kit_fight()
	fight.advance()
	fight.combatant("a").energy_milli = 0
	assert_str(fight.submit(FightAction.wait_for("heavy_strike"))).is_empty()
	var s := fight.summary()
	assert_dict(s.unit("a").action_uses).is_equal({"wait": 1})
	assert_dict(s.unit("a").tag_uses).is_equal({"banked": 1})


func test_the_answered_fight_summary_agrees_with_its_log_and_units() -> void:
	var fight := _answered_fight()
	assert_bool(fight.is_over()).is_true()
	var s := fight.summary()
	assert_int(s.outcome).is_equal(fight.outcome)
	assert_int(s.decisions).is_equal(fight.action_count)
	assert_int(s.squad.decisions + s.enemies.decisions).is_equal(fight.action_count)
	assert_int(s.ticks).is_equal(fight.timeline.current_tick)
	assert_float(s.grid_cost).is_equal(fight.result().grid_cost)
	assert_int(s.squad.energy_spent_milli).is_equal(fight.energy_spent_milli(Combatant.Side.PLAYER))
	# HP: the squad started at its request HP.
	var start := 0
	for m in fight.request.squad:
		start += m.hp
	assert_int(s.squad.hp_start).is_equal(start)
	assert_int(s.squad.hp_lost()).is_equal(A.squad_hp_lost(fight))
	# Counts read straight off the log.
	var combos := 0
	var staggers := 0
	var hits := 0
	for e in fight.events:
		var actor := fight.combatant(e.actor_id)
		if actor == null or actor.side != Combatant.Side.PLAYER:
			continue
		if e.is_combo():
			combos += 1
		if e.kind == FightEvent.Kind.STAGGER:
			staggers += 1
		if e.kind == FightEvent.Kind.HIT:
			hits += e.amount
	assert_int(s.squad.combos).is_equal(combos)
	assert_int(s.squad.staggers).is_equal(staggers)
	assert_int(s.squad.damage_dealt).is_equal(hits)
	# The answer uses the rework kit: setups, combos and Staggers all happen.
	assert_int(s.squad.setups).is_greater(0)
	assert_int(s.squad.combos).is_greater(0)
	assert_int(s.squad.staggers).is_greater(0)
	# Uses add up to the decisions, and the sides to their units.
	var uses := 0
	for id: String in s.squad.action_uses:
		uses += s.squad.action_uses[id]
	assert_int(uses).is_equal(s.squad.decisions)
	var unit_decisions := 0
	for t in s.units:
		if t.side == Combatant.Side.PLAYER:
			unit_decisions += t.decisions
	assert_int(unit_decisions).is_equal(s.squad.decisions)


func test_a_staggered_units_lost_turn_is_not_a_decision() -> void:
	var fight := _answered_fight()
	assert_int(FightLog.of_kind(fight.events, FightEvent.Kind.RECOVER).size()).is_greater(0)
	assert_int(fight.summary().decisions).is_equal(fight.decision_tags.size())


func test_to_dict_and_text_carry_the_numbers() -> void:
	var s := _answered_fight().summary()
	var d := s.to_dict()
	assert_int(d.decisions).is_equal(s.decisions)
	assert_int(d.squad.combos).is_equal(s.squad.combos)
	assert_int(d.units.size()).is_equal(s.units.size())
	assert_str(s.text()).contains("combos %d" % s.squad.combos)


func test_a_fight_that_has_not_started_summarises_to_nothing() -> void:
	var s := _kit_fight().summary()
	assert_int(s.decisions).is_equal(0)
	assert_int(s.squad.decisions).is_equal(0)
	assert_dict(s.squad.action_uses).is_empty()
	assert_int(s.squad.hp_lost()).is_equal(0)
