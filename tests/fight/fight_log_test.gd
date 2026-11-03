extends GdUnitTestSuite
## The one combat log (combat rework S6): Fight.events holds every event in
## order, each decision event carries its action and tags, and the log plus
## the request and seed replay the fight exactly (FightLog).

const H := preload("res://tests/fight/fight_test_helpers.gd")
const A := preload("res://tests/fight/archetypes/archetype_test_helpers.gd")
const V := preload("res://tests/fight/variants/variant_test_helpers.gd")
const C := preload("res://tests/fight/archetypes/charger_test.gd")


## The S5 Charger fight played to the end by the policy that answers it:
## Shred, Exposed, Heavy Strike, Brace, Staggers, recoveries, wind-ups and
## intent changes all happen in it.
static func _answered_fight() -> Fight:
	return A.play(A.charger_fight(), A.AnswerPolicy.new())


static func _count(events: Array[FightEvent], kind: FightEvent.Kind) -> int:
	return FightLog.of_kind(events, kind).size()


func test_the_log_holds_every_event_raised_in_order() -> void:
	var fight := A.charger_fight()
	var raised := A.record(fight)
	A.play(fight, A.AnswerPolicy.new())
	assert_bool(fight.is_over()).is_true()
	assert_int(fight.events.size()).is_greater(0)
	assert_array(fight.events).is_equal(raised)


func test_the_answered_fight_logs_every_kind_of_rework_event() -> void:
	var fight := _answered_fight()
	for kind: FightEvent.Kind in [FightEvent.Kind.SKILL, FightEvent.Kind.HIT, FightEvent.Kind.STATUS_APPLIED,
			FightEvent.Kind.STATUS_CONSUMED, FightEvent.Kind.PLATING, FightEvent.Kind.STAGGER,
			FightEvent.Kind.RECOVER, FightEvent.Kind.INTENT_CHANGED, FightEvent.Kind.DOWN]:
		assert_int(_count(fight.events, kind)).override_failure_message(
			"no %s in the log" % FightEvent.Kind.keys()[kind]).is_greater(0)


func test_last_events_are_the_tail_of_the_log() -> void:
	var fight := H.duel(H.stats(60, 8, 0, 50, 10), H.stats(80, 2, 0, 1, 10))
	fight.advance()
	var foe := fight.combatant("foe#1")
	fight.submit(FightAction.use("strike", foe.id))
	var first := fight.events.size()
	assert_array(FightLog.lines(fight.events)).is_equal(FightLog.lines(fight.last_events))
	var actor := fight.advance()
	var target := foe if actor.side == Combatant.Side.PLAYER else fight.combatant("ally")
	assert_str(fight.submit(FightAction.use("strike", target.id))).is_empty()
	assert_int(fight.events.size()).is_equal(first + fight.last_events.size())
	var tail: Array[FightEvent] = []
	tail.assign(fight.events.slice(first))
	assert_array(FightLog.lines(tail)).is_equal(FightLog.lines(fight.last_events))


func test_events_carry_the_tick_they_were_raised_at() -> void:
	var fight := _answered_fight()
	var tick := 0
	for e in fight.events:
		assert_int(e.tick).is_greater_equal(tick)
		tick = e.tick
	assert_int(tick).is_less_equal(fight.timeline.current_tick)
	assert_int(fight.events[-1].tick).is_greater(0)


func test_one_decision_event_per_decision_with_its_action_and_tags() -> void:
	var fight := _answered_fight()
	var decision_events := fight.events.filter(func(e: FightEvent) -> bool: return e.is_decision())
	assert_int(decision_events.size()).is_equal(fight.action_count)
	assert_int(fight.decisions().size()).is_equal(fight.action_count)
	for i in decision_events.size():
		var e: FightEvent = decision_events[i]
		assert_int(e.action_index).is_equal(i + 1)
		assert_bool(e.kind in [FightEvent.Kind.SKILL, FightEvent.Kind.WAIT]).is_true()
		assert_str(e.action.skill_id).is_equal(e.skill_id)
		assert_array(e.tags).is_equal(fight.decision_tags[i].tags)
		assert_bool(e.tags.is_empty()).is_false()
	# Events other than SKILL and WAIT carry no action.
	for e in fight.events:
		if not e.kind in [FightEvent.Kind.SKILL, FightEvent.Kind.WAIT]:
			assert_object(e.action).is_null()


func test_a_wind_up_wait_keeps_its_target_in_the_log() -> void:
	var fight: Fight = C._wound_up()
	var charger := fight.combatant(C.CHARGER)
	var waits := FightLog.of_kind(fight.events, FightEvent.Kind.WAIT).filter(
		func(e: FightEvent) -> bool: return e.actor_id == C.CHARGER)
	assert_int(waits.size()).is_greater(0)
	var wind_up: FightEvent = waits[-1]
	assert_str(wind_up.target_id).is_empty()
	assert_str(wind_up.action.target_id).is_equal(charger.committed.target_id())
	# The replay commits the same Ram at the same target.
	var again := A.charger_fight()
	assert_str(FightLog.replay_into(again, fight.decisions())).is_empty()
	assert_str(again.combatant(C.CHARGER).committed.target_id()).is_equal(charger.committed.target_id())


func test_hitting_the_wound_up_charger_is_reactive_in_the_log() -> void:
	var fight: Fight = C._wound_up()
	var actor: Combatant = C._next_ally(fight)
	assert_object(actor).is_not_null()
	assert_str(fight.submit(FightAction.use("strike", C.CHARGER))).is_empty()
	assert_array(fight.last_events[0].tags).contains(["offense", "reactive"])
	assert_int(fight.summary().squad.tag_uses.get("reactive", 0)).is_greater(0)


func test_the_decision_event_holds_a_copy_of_the_action() -> void:
	var fight := H.duel(H.stats(60, 8, 0, 50, 10), H.stats(80, 2, 0, 1, 10))
	fight.advance()
	var action := FightAction.use("strike", "foe#1")
	fight.submit(action)
	var logged := fight.events[0].action
	assert_object(logged).is_not_same(action)
	action.target_id = "changed"
	assert_str(logged.target_id).is_equal("foe#1")
	assert_str(fight.decisions()[0].target_id).is_equal("foe#1")


func test_a_headless_fight_replays_exactly_from_its_log() -> void:
	var tuning := CombatTuning.load_default()
	var squad: Array[SquadMemberSummary] = [
		H.member("ace", H.stats(40, 9, 2, 8, 12)), H.member("bee", H.stats(34, 7, 3, 9, 10))]
	var request := H.request(squad, 2)
	# The random policy draws from its rng; the replay reads only the log.
	var fight := HeadlessFightRunner.run(request, 7, RandomFightPolicy.new(), null, tuning)
	assert_bool(fight.is_over()).is_true()
	var again := FightLog.replay(request, 7, fight.events, tuning)
	_assert_same_fight(again, fight)


func test_the_answered_archetype_fight_replays_exactly_from_its_log() -> void:
	var fight := _answered_fight()
	var again := A.charger_fight()
	assert_str(FightLog.replay_into(again, fight.decisions())).is_empty()
	_assert_same_fight(again, fight)


func test_replaying_part_of_a_log_stops_at_that_decision() -> void:
	var fight := _answered_fight()
	var half: Array[FightAction] = []
	half.assign(fight.decisions().slice(0, 6))
	var again := A.charger_fight()
	assert_str(FightLog.replay_into(again, half)).is_empty()
	assert_int(again.action_count).is_equal(6)
	assert_array(FightLog.lines(_up_to(again.events, 5))).is_equal(FightLog.lines(_up_to(fight.events, 5)))


func test_a_refused_decision_stops_the_replay_and_says_why() -> void:
	var fight := H.duel(H.stats(60, 8, 0, 50, 10), H.stats(80, 2, 0, 1, 10))
	var bad: Array[FightAction] = [FightAction.use("strike", "nobody")]
	assert_str(FightLog.replay_into(fight, bad)).contains("decision 1")


func test_lines_hold_every_field() -> void:
	var fight := _answered_fight()
	var lines := FightLog.lines(fight.events)
	assert_int(lines.size()).is_equal(fight.events.size())
	var first: Dictionary = JSON.parse_string(lines[0])
	for key in ["kind", "action_index", "tick", "actor", "target", "skill", "amount", "hp", "action", "tags"]:
		assert_bool(first.has(key)).override_failure_message("missing " + key).is_true()


func test_for_action_returns_that_decisions_events() -> void:
	var fight := _answered_fight()
	var second := FightLog.for_action(fight.events, 2)
	assert_int(second.size()).is_greater(0)
	assert_bool(second[0].is_decision()).is_true()
	for e in second:
		assert_int(e.action_index).is_equal(2)


func test_a_fight_copy_carries_the_log_so_far() -> void:
	var fight := A.charger_fight()
	var policy := A.AnswerPolicy.new()
	var enemy_policy := IntentFightPolicy.new(fight.planner())
	for i in 5:
		var actor := fight.advance()
		fight.submit((policy if actor.side == Combatant.Side.PLAYER else enemy_policy).choose(fight, actor, null))
	fight.advance()
	var copy := FightCopy.of(fight)
	assert_array(FightLog.lines(copy.events)).is_equal(FightLog.lines(fight.events))
	copy.submit(SimpleFightPolicy.new().choose(copy, copy.pending_actor, null))
	assert_int(copy.events.size()).is_greater(fight.events.size())
	assert_int(fight.decisions().size()).is_equal(5)


func test_resist_knockback_raises_a_knockback_event() -> void:
	var t := V.tuning_with(FightVariants.ELASTICITY, FightVariants.ELASTICITY_KNOCKBACK)
	var fight := H.duel(H.stats(50, 5, 0, 50, 10), H.stats(50, 1, 0, 10, 10, 1), t)
	fight.advance()
	var foe := fight.combatant("foe#1")
	foe.gauge = 500
	fight.submit(FightAction.use("strike", foe.id))
	var pushed := FightLog.of_kind(fight.last_events, FightEvent.Kind.KNOCKBACK)
	assert_int(pushed.size()).is_equal(1)
	assert_int(pushed[0].gauge_before).is_equal(500)
	assert_int(pushed[0].gauge_after).is_equal(foe.gauge)
	assert_int(pushed[0].amount).is_equal(500 - foe.gauge)
	assert_str(pushed[0].target_id).is_equal(foe.id)


func test_no_knockback_event_under_the_default_elasticity() -> void:
	var fight := H.duel(H.stats(50, 5, 0, 50, 10), H.stats(50, 1, 0, 10, 10, 1))
	fight.advance()
	fight.combatant("foe#1").gauge = 500
	fight.submit(FightAction.use("strike", "foe#1"))
	assert_int(FightLog.of_kind(fight.last_events, FightEvent.Kind.KNOCKBACK).size()).is_equal(0)


## The events of the first `count` decisions (and anything between them).
static func _up_to(events: Array[FightEvent], count: int) -> Array[FightEvent]:
	var out: Array[FightEvent] = []
	for e in events:
		if e.action_index <= count:
			out.append(e)
	return out


## The same events (every field), the same log text, result and summary.
func _assert_same_fight(again: Fight, original: Fight) -> void:
	assert_int(again.action_count).is_equal(original.action_count)
	assert_array(FightLog.lines(again.events)).is_equal(FightLog.lines(original.events))
	assert_array(_without_policy_lines(again.log_lines)).is_equal(_without_policy_lines(original.log_lines))
	assert_int(again.outcome).is_equal(original.outcome)
	assert_float(again.result().grid_cost).is_equal(original.result().grid_cost)
	assert_dict(again.summary().to_dict()).is_equal(original.summary().to_dict())


## The runner logs a refused policy choice itself; that is not a fight event.
static func _without_policy_lines(lines: PackedStringArray) -> Array:
	return Array(lines).filter(func(l: String) -> bool: return not l.begins_with("  policy refused"))
