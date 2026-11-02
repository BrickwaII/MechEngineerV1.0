extends GdUnitTestSuite
## Combat rework S2: an action's recovery pushes its user back on the ATB
## timeline, and TimelineOps moves units for other rules (delay, advance,
## knockback). Wait stays free: no energy, no recovery.

const H := preload("res://tests/fight/fight_test_helpers.gd")

## Recovery of the test's heavy action, in percent of a turn.
const HEAVY_RECOVERY := 50


## The default tuning plus two test actions that differ only in recovery.
func _tuning() -> CombatTuning:
	var t := CombatTuning.load_default()
	t.skills["light"] = CombatSkill.from_dict("light", {"name": "Light", "energy_cost": 1, "power_percent": 50})
	t.skills["heavy"] = CombatSkill.from_dict("heavy",
		{"name": "Heavy", "energy_cost": 1, "power_percent": 50, "recovery": HEAVY_RECOVERY})
	t.player_skills.assign(["light", "heavy"])
	return t


## One fast ally with light and heavy against one slow foe that cannot fall.
func _fight(t: CombatTuning = null) -> Fight:
	t = t if t != null else _tuning()
	var table := H.table({"foe": H.enemy_def("Foe", H.stats(9999, 1, 0, 1, 10), ["light"])}, "foe")
	var squad: Array[SquadMemberSummary] = [H.member("ally", H.stats(500, 5, 0, 7, 50))]
	return Fight.new(H.request(squad), 1, t, table)


func _kinds(fight: Fight) -> Array:
	return fight.last_events.map(func(e: FightEvent) -> FightEvent.Kind: return e.kind)


## The ally's turns before tick `span`, using `skill_id` every turn.
func _ally_turns(skill_id: String, span: int) -> int:
	var fight := _fight()
	var turns := 0
	var unit := fight.advance()
	while unit != null and fight.timeline.current_tick < span:
		if unit.side == Combatant.Side.PLAYER:
			turns += 1
			assert_str(fight.submit(FightAction.use(skill_id, "foe#1"))).is_empty()
		else:
			assert_str(fight.submit(FightAction.use("light", "ally"))).is_empty()
		unit = fight.advance()
	return turns


func test_turn_gauge_is_a_share_of_the_turn_threshold() -> void:
	var t := _tuning()
	assert_int(TimelineOps.turn_gauge(100, t)).is_equal(t.turn_threshold())
	@warning_ignore("integer_division")
	assert_int(TimelineOps.turn_gauge(30, t)).is_equal(t.turn_threshold() * 30 / 100)
	assert_int(TimelineOps.recovery_gauge(t.skill("heavy"), t)).is_equal(TimelineOps.turn_gauge(HEAVY_RECOVERY, t))
	assert_int(TimelineOps.recovery_gauge(t.skill("light"), t)).is_equal(0)


func test_a_heavy_action_yields_fewer_turns_over_a_fixed_span() -> void:
	var light := _ally_turns("light", 400)
	var heavy := _ally_turns("heavy", 400)
	assert_int(light).is_greater(0)
	assert_int(heavy).is_less(light)


func test_recovery_pushes_the_actor_back_after_its_effects() -> void:
	var fight := _fight()
	var ally := fight.advance()
	var overflow := ally.gauge - fight.timeline.threshold
	var cost := TimelineOps.recovery_gauge(ally.skill("heavy"), fight.tuning)
	assert_str(fight.submit(FightAction.use("heavy", "foe#1"))).is_empty()
	assert_int(ally.gauge).is_equal(overflow - cost)
	assert_array(_kinds(fight)).is_equal([FightEvent.Kind.SKILL, FightEvent.Kind.HIT, FightEvent.Kind.RECOVERY])
	var e: FightEvent = fight.last_events[-1]
	assert_str(e.actor_id).is_equal("ally")
	assert_str(e.target_id).is_equal("ally")
	assert_str(e.skill_id).is_equal("heavy")
	assert_int(e.amount).is_equal(cost)
	assert_int(e.gauge_after).is_equal(ally.gauge)


func test_an_action_without_recovery_raises_no_timeline_event() -> void:
	var fight := _fight()
	var ally := fight.advance()
	var overflow := ally.gauge - fight.timeline.threshold
	assert_str(fight.submit(FightAction.use("light", "foe#1"))).is_empty()
	assert_int(ally.gauge).is_equal(overflow)
	assert_array(_kinds(fight)).is_equal([FightEvent.Kind.SKILL, FightEvent.Kind.HIT])


func test_recovery_orders_the_heavy_user_after_the_light_user() -> void:
	# Two equal allies; the one that used heavy acts after the one that used light.
	var t := _tuning()
	var table := H.table({"foe": H.enemy_def("Foe", H.stats(9999, 1, 0, 1, 10), ["light"])}, "foe")
	var squad: Array[SquadMemberSummary] = [
		H.member("a", H.stats(500, 5, 0, 7, 50)), H.member("b", H.stats(500, 5, 0, 7, 50))]
	var fight := Fight.new(H.request(squad), 1, t, table)
	assert_str(fight.advance().id).is_equal("a")
	assert_str(fight.submit(FightAction.use("heavy", "foe#1"))).is_empty()
	assert_str(fight.advance().id).is_equal("b")
	assert_str(fight.submit(FightAction.use("light", "foe#1"))).is_empty()
	var order := fight.upcoming(3).map(func(e: TimelineEntry) -> String: return e.combatant_id)
	assert_int(order.find("b")).is_less(order.find("a"))


func test_delay_may_push_a_unit_into_debt() -> void:
	var fight := _fight()
	var ally := fight.advance()
	assert_str(fight.submit(FightAction.use("light", "foe#1"))).is_empty()
	var foe := fight.combatant("foe#1")
	var before := foe.gauge
	var moved := TimelineOps.delay(fight, foe, before + 300, ally)
	assert_int(moved).is_equal(before + 300)
	assert_int(foe.gauge).is_equal(-300)
	var e: FightEvent = fight.last_events[-1]
	assert_int(e.kind).is_equal(FightEvent.Kind.DELAY)
	assert_str(e.actor_id).is_equal("ally")
	assert_str(e.target_id).is_equal("foe#1")
	assert_int(e.gauge_before).is_equal(before)
	assert_int(e.gauge_after).is_equal(-300)


func test_a_delayed_unit_acts_later() -> void:
	var plain := _fight()
	plain.advance()
	plain.submit(FightAction.use("light", "foe#1"))
	var delayed := _fight()
	delayed.advance()
	delayed.submit(FightAction.use("light", "foe#1"))
	TimelineOps.delay(delayed, delayed.combatant("foe#1"), 400)
	var foe_tick := func(f: Fight) -> int:
		for e in f.upcoming(6):
			if e.combatant_id == "foe#1":
				return e.tick
		return -1
	assert_int(foe_tick.call(delayed)).is_greater(foe_tick.call(plain))


func test_knockback_moves_like_delay_and_reports_knockback() -> void:
	var fight := _fight()
	fight.advance()
	var foe := fight.combatant("foe#1")
	var before := foe.gauge
	assert_int(TimelineOps.knockback(fight, foe, 250)).is_equal(250)
	assert_int(foe.gauge).is_equal(before - 250)
	assert_int(fight.last_events[-1].kind).is_equal(FightEvent.Kind.KNOCKBACK)


func test_advance_stops_at_the_turn_threshold() -> void:
	var fight := _fight()
	fight.advance()
	var foe := fight.combatant("foe#1")
	var threshold := fight.timeline.threshold
	foe.gauge = threshold - 10
	assert_int(TimelineOps.advance(fight, foe, 500)).is_equal(10)
	assert_int(foe.gauge).is_equal(threshold)
	assert_int(fight.last_events[-1].kind).is_equal(FightEvent.Kind.ADVANCE)
	# A full gauge does not grow: no second turn for one fill, and no event.
	var events := fight.last_events.size()
	assert_int(TimelineOps.advance(fight, foe, 500)).is_equal(0)
	assert_int(foe.gauge).is_equal(threshold)
	assert_int(fight.last_events.size()).is_equal(events)


func test_a_move_of_nothing_raises_no_event() -> void:
	var fight := _fight()
	fight.advance()
	var foe := fight.combatant("foe#1")
	var events := fight.last_events.size()
	assert_int(TimelineOps.delay(fight, foe, 0)).is_equal(0)
	assert_int(TimelineOps.knockback(fight, foe, -5)).is_equal(0)
	assert_int(fight.last_events.size()).is_equal(events)


func test_a_delay_on_a_waiting_unit_lands_after_its_next_action() -> void:
	var fight := _fight()
	var ally := fight.advance()
	assert_str(fight.submit(FightAction.wait_for("heavy"))).is_empty()
	var held := ally.gauge
	TimelineOps.delay(fight, ally, 200)
	# The wait keeps its full gauge; the delay is held.
	assert_int(ally.gauge).is_equal(held)
	assert_int(ally.held_delay).is_equal(200)
	assert_bool(ally.clone_for_preview().held_delay == 200).is_true()
	assert_object(fight.advance()).is_same(ally)
	var overflow := ally.gauge - fight.timeline.threshold
	assert_str(fight.submit(FightAction.use("light", "foe#1"))).is_empty()
	assert_int(ally.gauge).is_equal(maxi(0, overflow) - 200)
	assert_int(ally.held_delay).is_equal(0)


func test_advance_on_a_waiting_unit_only_cancels_held_delay() -> void:
	var fight := _fight()
	var ally := fight.advance()
	fight.submit(FightAction.wait_for("heavy"))
	var held := ally.gauge
	TimelineOps.delay(fight, ally, 200)
	assert_int(TimelineOps.advance(fight, ally, 500)).is_equal(200)
	assert_int(ally.held_delay).is_equal(0)
	assert_int(ally.gauge).is_equal(held)


func test_wait_is_free_and_has_no_recovery() -> void:
	var fight := _fight()
	var ally := fight.advance()
	ally.energy_milli = 0
	var gauge := ally.gauge
	assert_str(fight.check_action(FightAction.wait_for("heavy"))).is_empty()
	assert_str(fight.submit(FightAction.wait_for("heavy"))).is_empty()
	assert_int(ally.energy_spent_milli).is_equal(0)
	assert_int(ally.gauge).is_equal(gauge)
	assert_array(_kinds(fight)).is_equal([FightEvent.Kind.WAIT])


func test_wait_banks_energy_by_default() -> void:
	# Combat rework question 1: Wait's "bonus charge" is energy (d-wait banked).
	var fight := _fight()
	var ally := fight.advance()
	assert_bool(fight.tuning.variants.is_chosen(FightVariants.WAIT_FORM, FightVariants.WAIT_BANKED)).is_true()
	assert_int(ally.wait_recharge_milli).is_greater(ally.recharge_milli)
