extends GdUnitTestSuite
## ATB wait mode: time runs only between decisions, never during one.

const H := preload("res://tests/fight/fight_test_helpers.gd")


func _fight() -> Fight:
	return H.duel(H.stats(50, 10, 0, 7, 10), H.stats(50, 5, 0, 4, 10))


func test_advance_stops_at_the_first_ready_unit_and_waits() -> void:
	var fight := _fight()
	var unit := fight.advance()
	assert_object(unit).is_not_null()
	assert_bool(fight.is_awaiting_decision()).is_true()
	assert_object(fight.pending_actor).is_same(unit)


func test_no_time_passes_while_a_decision_is_pending() -> void:
	var fight := _fight()
	var unit := fight.advance()
	var tick := fight.timeline.current_tick
	var energies := fight.combatants.map(func(c: Combatant) -> int: return c.energy_milli)
	for i in 20:
		assert_object(fight.advance()).is_same(unit)
	assert_int(fight.timeline.current_tick).is_equal(tick)
	assert_array(fight.combatants.map(func(c: Combatant) -> int: return c.energy_milli)).is_equal(energies)


func test_submit_resumes_time() -> void:
	var fight := _fight()
	fight.advance()
	var tick := fight.timeline.current_tick
	assert_str(fight.submit(FightAction.use("strike", "foe#1"))).is_empty()
	assert_bool(fight.is_awaiting_decision()).is_false()
	fight.advance()
	assert_int(fight.timeline.current_tick).is_greater(tick)


func test_submit_without_a_pending_unit_is_refused() -> void:
	var fight := _fight()
	assert_str(fight.submit(FightAction.use("strike", "foe#1"))).is_not_empty()
	assert_int(fight.action_count).is_equal(0)


func test_bad_actions_are_refused_and_change_nothing() -> void:
	var fight := _fight()
	var unit := fight.advance()
	var bad: Array[FightAction] = [
		null,
		FightAction.use("no_such_skill", "foe#1"),
		FightAction.use("strike", "nobody"),
		FightAction.use("strike", unit.id),
	]
	for action in bad:
		assert_str(fight.submit(action)).is_not_empty()
	fight.combatant("foe#1").hp = 0
	assert_str(fight.submit(FightAction.use("strike", "foe#1"))).is_not_empty()
	fight.combatant("foe#1").hp = 50
	assert_object(fight.pending_actor).is_same(unit)
	assert_int(fight.action_count).is_equal(0)
	assert_array(fight.action_tags).is_empty()


func test_turns_alternate_by_speed_through_decisions() -> void:
	var fight := _fight()
	var order: Array[String] = []
	for i in 6:
		var unit := fight.advance()
		order.append(unit.id)
		var target: Combatant = fight.opponents_of(unit)[0]
		fight.submit(FightAction.use("strike", target.id))
	# Speeds 7 and 4: the ally acts at ticks 15, 29, 43, 58; the foe at 25, 50.
	assert_array(order).contains_exactly(["ally", "foe#1", "ally", "ally", "foe#1", "ally"])
