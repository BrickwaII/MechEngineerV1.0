extends GdUnitTestSuite
## Exposed and the Heavy payoff in real fights (combat rework S3): Shred puts
## Exposed on, the next hit uses it up for +50%, it wears off when the holder
## acts first, and Shred then Heavy Strike beats two Heavy Strikes on damage
## per energy.

const T := preload("res://tests/fight/intent/intent_test_helpers.gd")

## Fast enough to act before the slow foe, twice in a row (roster order).
const FAST := 11
const SLOW := 3


static func _tuning() -> CombatTuning:
	var tuning := CombatTuning.load_default()
	tuning.player_skills.assign(["strike", "shred", "heavy_strike"])
	return tuning


## Allies "a" and "b" (both fast, big batteries) against one sturdy foe whose
## speed is `foe_speed`.
static func _fight(foe_speed := SLOW) -> Fight:
	var ally := T.stats(60, 12, 3, FAST, 20)
	var foe := T.stats(400, 6, 4, foe_speed, 10)
	return T.fight(
		[{"id": "a", "stats": ally}, {"id": "b", "stats": ally}],
		[{"id": "foe#1", "stats": foe, "skills": ["strike"]}], _tuning())


## Runs time to the next decision and asserts whose it is.
func _next(fight: Fight, expected_id: String) -> Combatant:
	var actor := fight.advance()
	assert_str(actor.id).is_equal(expected_id)
	return actor


func _submit(fight: Fight, action: FightAction) -> Array[FightEvent]:
	assert_str(fight.submit(action)).is_empty()
	return fight.last_events.duplicate()


static func _kinds(events: Array[FightEvent]) -> Array:
	return events.map(func(e: FightEvent) -> String: return FightEvent.Kind.keys()[e.kind])


static func _damage(events: Array[FightEvent]) -> int:
	var sum := 0
	for e in events:
		if e.kind == FightEvent.Kind.HIT:
			sum += e.amount
	return sum


func test_shred_costs_energy_hits_twice_and_applies_exposed() -> void:
	var fight := _fight()
	var a := _next(fight, "a")
	var foe := fight.combatant("foe#1")
	var shred := a.skill("shred")
	assert_int(shred.energy_cost).is_greater(0)
	var energy_before := a.energy_milli
	var events := _submit(fight, FightAction.use("shred", foe.id))
	assert_int(a.energy_milli).is_equal(energy_before - shred.energy_cost_milli())
	assert_array(_kinds(events)).is_equal(["SKILL", "HIT", "HIT", "STATUS_APPLIED"])
	# Neither of Shred's own hits gets the bonus: Exposed goes on after them.
	var plain := DamageRules.damage(a.stats, foe.stats, shred, fight.tuning)
	assert_int(events[1].amount).is_equal(plain)
	assert_int(events[2].amount).is_equal(plain)
	assert_int(events[1].status_bonus_percent).is_equal(0)
	var applied := events[3]
	assert_str(applied.status_id).is_equal("exposed")
	assert_str(applied.actor_id).is_equal("a")
	assert_str(applied.target_id).is_equal(foe.id)
	assert_bool(foe.has_status("exposed")).is_true()
	assert_str(fight.log_text()).contains("Foe 1 is Exposed")


func test_exposed_adds_half_to_the_next_hit_and_is_used_up() -> void:
	var fight := _fight()
	var foe := fight.combatant("foe#1")
	_next(fight, "a")
	_submit(fight, FightAction.use("shred", foe.id))
	var b := _next(fight, "b")
	var strike := b.skill("strike")
	var plain := DamageRules.damage(b.stats, foe.stats, strike, fight.tuning)
	var events := _submit(fight, FightAction.use("strike", foe.id))
	assert_array(_kinds(events)).is_equal(["SKILL", "HIT", "STATUS_CONSUMED"])
	@warning_ignore("integer_division")
	assert_int(events[1].amount).is_equal(plain * 150 / 100)
	assert_int(events[1].status_bonus_percent).is_equal(50)
	assert_str(events[2].status_id).is_equal("exposed")
	assert_bool(foe.has_status("exposed")).is_false()
	assert_str(fight.log_text()).contains("(+50% Exposed)")
	assert_str(fight.log_text()).contains("Foe 1's Exposed is used up")


func test_a_second_shred_refreshes_exposed_without_stacking() -> void:
	var fight := _fight()
	var foe := fight.combatant("foe#1")
	_next(fight, "a")
	_submit(fight, FightAction.use("shred", foe.id))
	_next(fight, "b")
	var events := _submit(fight, FightAction.use("shred", foe.id))
	# The first hit used Exposed up; the action puts it back on, once.
	assert_array(_kinds(events)).is_equal(["SKILL", "HIT", "STATUS_CONSUMED", "HIT", "STATUS_APPLIED"])
	assert_int(foe.statuses.size()).is_equal(1)
	assert_int(foe.status("exposed").stacks).is_equal(1)
	assert_str(foe.status("exposed").source_id).is_equal("b")


func test_exposed_wears_off_when_the_enemy_acts_before_the_payoff() -> void:
	# The foe is faster than b, so it acts between a's Shred and b's Heavy.
	var ally_fast := T.stats(60, 12, 3, FAST, 20)
	var ally_slow := T.stats(60, 12, 3, SLOW, 20)
	var fight := T.fight(
		[{"id": "a", "stats": ally_fast}, {"id": "b", "stats": ally_slow}],
		[{"id": "foe#1", "stats": T.stats(400, 6, 4, 9, 10), "skills": ["strike"]}], _tuning())
	var foe := fight.combatant("foe#1")
	_next(fight, "a")
	_submit(fight, FightAction.use("shred", foe.id))
	assert_bool(foe.has_status("exposed")).is_true()
	_next(fight, "foe#1")
	var foe_events := _submit(fight, FightAction.use("strike", "a"))
	assert_array(_kinds(foe_events)).is_equal(["SKILL", "STATUS_EXPIRED", "HIT"])
	assert_str(foe_events[1].status_id).is_equal("exposed")
	assert_str(foe_events[1].actor_id).is_equal(foe.id)
	assert_str(foe_events[1].target_id).is_equal(foe.id)
	assert_bool(foe.has_status("exposed")).is_false()
	assert_str(fight.log_text()).contains("Foe 1's Exposed wears off")
	# The payoff comes too late: plain Heavy Strike damage, no bonus.
	var b := _next(fight, "b")
	var heavy := b.skill("heavy_strike")
	var events := _submit(fight, FightAction.use("heavy_strike", foe.id))
	# RECOVERY last: Heavy Strike costs time as well (combat rework S2).
	assert_array(_kinds(events)).is_equal(["SKILL", "HIT", "RECOVERY"])
	assert_int(events[1].amount).is_equal(DamageRules.damage(b.stats, foe.stats, heavy, fight.tuning))
	assert_int(events[1].payoff_bonus_percent).is_equal(0)


func test_a_wait_also_ends_exposed() -> void:
	var fight := T.fight(
		[{"id": "a", "stats": T.stats(60, 12, 3, FAST, 20)}],
		[{"id": "foe#1", "stats": T.stats(400, 6, 4, 9, 10), "skills": ["strike", "overload"]}], _tuning())
	var foe := fight.combatant("foe#1")
	_next(fight, "a")
	_submit(fight, FightAction.use("shred", foe.id))
	_next(fight, "foe#1")
	var events := _submit(fight, FightAction.wait_for("overload"))
	assert_array(_kinds(events)).is_equal(["WAIT", "STATUS_EXPIRED"])
	assert_bool(foe.has_status("exposed")).is_false()


func test_the_holder_keeps_exposed_while_others_act() -> void:
	var fight := _fight()
	var foe := fight.combatant("foe#1")
	var a := _next(fight, "a")
	_submit(fight, FightAction.use("shred", foe.id))
	_next(fight, "b")
	# b acts on someone else's behalf (a wait): the foe still holds Exposed.
	_submit(fight, FightAction.wait_for("heavy_strike"))
	assert_bool(foe.has_status("exposed")).is_true()
	assert_bool(a.has_status("exposed")).is_false()


func test_heavy_payoff_against_exposed_stacks_after_the_exposed_bonus() -> void:
	var fight := _fight()
	var foe := fight.combatant("foe#1")
	_next(fight, "a")
	_submit(fight, FightAction.use("shred", foe.id))
	var b := _next(fight, "b")
	var heavy := b.skill("heavy_strike")
	assert_str(heavy.payoff_condition).is_equal("exposed")
	var plain := DamageRules.damage(b.stats, foe.stats, heavy, fight.tuning)
	var events := _submit(fight, FightAction.use("heavy_strike", foe.id))
	var hit := events[1]
	assert_int(hit.status_bonus_percent).is_equal(50)
	assert_int(hit.payoff_bonus_percent).is_equal(heavy.payoff_bonus_percent)
	@warning_ignore("integer_division")
	assert_int(hit.amount).is_equal(plain * 150 / 100 * (100 + heavy.payoff_bonus_percent) / 100)
	assert_str(fight.log_text()).contains("(+%d%% payoff)" % heavy.payoff_bonus_percent)


func test_exposed_then_heavy_beats_two_heavies_on_damage_per_energy() -> void:
	# Combo: a Shreds, then b Heavy Strikes the Exposed foe.
	var combo := _fight()
	var foe := combo.combatant("foe#1")
	var a := _next(combo, "a")
	var b := _next_after(combo, a, FightAction.use("shred", foe.id), "b")
	var combo_damage := _damage(combo.last_events)
	var combo_energy := a.energy_spent_milli
	_submit(combo, FightAction.use("heavy_strike", foe.id))
	combo_damage += _damage(combo.last_events)
	combo_energy += b.energy_spent_milli
	# Greedy: both Heavy Strike, on an identical fight.
	var greedy := _fight()
	var foe2 := greedy.combatant("foe#1")
	var a2 := _next(greedy, "a")
	var b2 := _next_after(greedy, a2, FightAction.use("heavy_strike", foe2.id), "b")
	var greedy_damage := _damage(greedy.last_events)
	_submit(greedy, FightAction.use("heavy_strike", foe2.id))
	greedy_damage += _damage(greedy.last_events)
	var greedy_energy := a2.energy_spent_milli + b2.energy_spent_milli
	assert_int(combo_energy).is_greater(0)
	assert_int(greedy_energy).is_greater(0)
	# combo_damage / combo_energy > greedy_damage / greedy_energy, in whole numbers.
	assert_int(combo_damage * greedy_energy).override_failure_message(
		"combo %d dmg / %d milli vs greedy %d dmg / %d milli" % [combo_damage, combo_energy, greedy_damage, greedy_energy]
	).is_greater(greedy_damage * combo_energy)
	# The combo is also cheaper outright.
	assert_int(combo_energy).is_less(greedy_energy)


## Submits `action` for the pending unit, then runs to the next decision and
## asserts it is `expected_id`'s.
func _next_after(fight: Fight, _actor: Combatant, action: FightAction, expected_id: String) -> Combatant:
	_submit(fight, action)
	return _next(fight, expected_id)


func test_fight_copy_carries_statuses_and_does_not_share_them() -> void:
	var fight := _fight()
	var foe := fight.combatant("foe#1")
	_next(fight, "a")
	_submit(fight, FightAction.use("shred", foe.id))
	_next(fight, "b")
	var copy := FightCopy.of(fight)
	var foe_copy := copy.combatant(foe.id)
	assert_bool(foe_copy.has_status("exposed")).is_true()
	assert_str(copy.submit(FightAction.use("strike", foe.id))).is_empty()
	assert_bool(foe_copy.has_status("exposed")).is_false()
	assert_bool(foe.has_status("exposed")).is_true()


func test_choice_preview_lists_status_changes() -> void:
	var fight := _fight()
	var foe := fight.combatant("foe#1")
	_next(fight, "a")
	var preview := FightPreview.new()
	var shred := preview.preview_choice(fight, FightAction.use("shred", foe.id))
	assert_array(shred.status_changes.get(foe.id, [])).is_equal(["exposed"])
	_submit(fight, FightAction.use("shred", foe.id))
	_next(fight, "b")
	var strike := preview.preview_choice(fight, FightAction.use("strike", foe.id))
	assert_array(strike.status_changes.get(foe.id, ["missing"])).is_empty()
	# The preview's damage counts Exposed and the payoff, as the fight will.
	var heavy := preview.preview_choice(fight, FightAction.use("heavy_strike", foe.id))
	var shown := heavy.effect_on(foe.id).damage.value
	var events := _submit(fight, FightAction.use("heavy_strike", foe.id))
	assert_int(shown).is_equal(events[1].amount)
