extends GdUnitTestSuite
## Enemy intent from personality weights, with no UI.

const T := preload("res://tests/fight/intent/intent_test_helpers.gd")


func _duel(enemy_skills: Array, enemy_battery := 10) -> Fight:
	return T.fight(
		[{"id": "bolt", "stats": T.stats(100, 10, 0, 4, 10)}],
		[{"id": "foe#1", "stats": T.stats(100, 10, 0, 4, enemy_battery), "skills": enemy_skills}])


func test_plans_one_intent_per_living_enemy_and_none_for_allies() -> void:
	var f := T.healer_fight()
	var intents := T.healer_planner().plan_all(f)
	assert_array(intents.keys()).contains_exactly(["medic#1", "grunt#1"])
	for id: String in intents:
		assert_str(intents[id].unit_id).is_equal(id)
		assert_str(intents[id].target_id()).is_equal("bolt")
	f.combatant("grunt#1").hp = 0
	assert_array(T.healer_planner().plan_all(f).keys()).contains_exactly(["medic#1"])


func test_plans_are_deterministic() -> void:
	var f := T.healer_fight()
	var a := T.healer_planner().plan_all(f)
	var b := T.healer_planner().plan_all(f)
	for id: String in a:
		assert_bool(a[id].same_as(b[id])).is_true()
		assert_float(a[id].score).is_equal(b[id].score)


func test_planning_does_not_change_the_fight() -> void:
	var f := T.healer_fight()
	f.advance()
	var before := T.snapshot(f)
	T.healer_planner().plan_all(f)
	assert_str(T.snapshot(f)).is_equal(before)


func test_aggressive_spends_on_the_heavy_skill_and_defensive_saves_energy() -> void:
	# Strike: 10 damage for 0 energy. Heavy Strike: 15 damage for 4 energy.
	var f := _duel(["strike", "heavy_strike"])
	var aggressive := T.planner({"foe#1": T.p(-1.0)}).plan(f, f.combatant("foe#1"))
	var defensive := T.planner({"foe#1": T.p(1.0)}).plan(f, f.combatant("foe#1"))
	assert_str(aggressive.skill_id()).is_equal("heavy_strike")
	assert_str(defensive.skill_id()).is_equal("strike")
	assert_int(aggressive.amount).is_equal(15)
	assert_int(defensive.amount).is_equal(10)


func test_supportive_heals_a_hurt_ally_and_solitary_attacks() -> void:
	var f := T.healer_fight()
	f.combatant("grunt#1").hp = 10
	var supportive := T.planner({"medic#1": T.p(0.0, 1.0)}).plan(f, f.combatant("medic#1"))
	var solitary := T.planner({"medic#1": T.p(0.0, -1.0)}).plan(f, f.combatant("medic#1"))
	assert_int(supportive.kind).is_equal(UnitIntent.Kind.HEAL)
	assert_str(supportive.target_id()).is_equal("grunt#1")
	assert_int(supportive.amount).is_equal(8)
	assert_int(solitary.kind).is_equal(UnitIntent.Kind.ATTACK)
	assert_str(solitary.target_id()).is_equal("bolt")


func test_reactive_hits_back_at_the_last_attacker_and_methodical_finishes_the_weakest() -> void:
	var f := T.fight(
		[
			{"id": "ace", "stats": T.stats(100, 5, 0, 20, 10)},
			{"id": "bea", "stats": T.stats(100, 5, 0, 1, 10), "hp": 50},
		],
		[{"id": "foe#1", "stats": T.stats(200, 10, 0, 2, 10), "skills": ["strike"]}])
	assert_str(f.advance().id).is_equal("ace")
	assert_str(f.submit(FightAction.use("strike", "foe#1"))).is_empty()
	var reactive := T.planner({"foe#1": T.p(0.0, 0.0, -1.0)}).plan(f, f.combatant("foe#1"))
	var methodical := T.planner({"foe#1": T.p(0.0, 0.0, 1.0)}).plan(f, f.combatant("foe#1"))
	assert_str(reactive.target_id()).is_equal("ace")
	assert_str(methodical.target_id()).is_equal("bea")


func test_methodical_waits_for_a_big_skill_and_reactive_strikes_now() -> void:
	# 5 of 10 energy: Overload (9) is out of reach until the unit waits.
	var f := _duel(["strike", "overload"])
	var methodical := T.planner({"foe#1": T.p(0.0, 0.0, 1.0)}).plan(f, f.combatant("foe#1"))
	var reactive := T.planner({"foe#1": T.p(0.0, 0.0, -1.0)}).plan(f, f.combatant("foe#1"))
	assert_int(methodical.kind).is_equal(UnitIntent.Kind.WAIT)
	assert_str(methodical.skill_id()).is_equal("overload")
	assert_int(methodical.action.kind).is_equal(FightAction.Kind.WAIT)
	assert_int(reactive.kind).is_equal(UnitIntent.Kind.ATTACK)
	assert_str(reactive.skill_id()).is_equal("strike")


func test_never_plans_a_skill_the_unit_can_never_afford() -> void:
	# A 6-point battery can never hold Overload's 9.
	var f := _duel(["strike", "overload"], 6)
	for intent in T.planner({"foe#1": T.p(0.0, 0.0, 1.0)}).rank(f, f.combatant("foe#1")):
		assert_str(intent.skill_id()).is_equal("strike")


func test_a_kill_is_worth_more_than_its_damage() -> void:
	var f := T.fight(
		[
			{"id": "ace", "stats": T.stats(100, 5, 0, 4, 10)},
			{"id": "bea", "stats": T.stats(100, 5, 0, 4, 10), "hp": 9},
		],
		[{"id": "foe#1", "stats": T.stats(100, 10, 0, 2, 10), "skills": ["strike"]}])
	# Both take 10. Reactive puts no weight on focus and nobody has acted yet,
	# so only the kill bonus separates them.
	var intent := T.planner({"foe#1": T.p(0.0, 0.0, -1.0)}).plan(f, f.combatant("foe#1"))
	assert_str(intent.target_id()).is_equal("bea")


func test_rank_lists_every_option_best_first() -> void:
	var f := _duel(["strike", "heavy_strike"])
	var ranked := T.planner({"foe#1": T.p(-1.0)}).rank(f, f.combatant("foe#1"))
	assert_int(ranked.size()).is_equal(2)
	assert_float(ranked[0].score).is_greater_equal(ranked[1].score)


func test_default_data_is_complete() -> void:
	assert_array(IntentWeights.load_default().validate()).is_empty()
	assert_array(EnemyPersonalities.load_default().missing_from(EnemyTable.load_default())).is_empty()
	assert_str(IntentWeights.load_default().role_of("repair")).is_equal(IntentWeights.ROLE_HEAL)
	assert_str(IntentWeights.load_default().role_of("strike")).is_equal(IntentWeights.ROLE_ATTACK)


func test_enemies_get_their_personality_from_data() -> void:
	var personalities := EnemyPersonalities.load_default()
	assert_str(personalities.for_unit("rust_hound#2").get_tag()).is_equal("aggressive")
	assert_str(personalities.for_unit("sentry_turret#1").get_tag()).is_equal("methodical")
	assert_str(personalities.for_unit("unknown#1").get_tag()).is_equal(Personality.BALANCED_TAG)


func test_weights_lean_with_personality() -> void:
	var w := IntentWeights.load_default()
	assert_float(w.weight(IntentWeights.HEAL, T.p(0.0, 1.0))).is_greater(w.weight(IntentWeights.HEAL, T.p(0.0, -1.0)))
	assert_float(w.weight(IntentWeights.DAMAGE, T.p(-1.0))).is_greater(w.weight(IntentWeights.DAMAGE, T.p(1.0)))
	assert_float(w.weight(IntentWeights.RETALIATE, T.p(0.0, 0.0, -1.0))).is_greater(w.weight(IntentWeights.RETALIATE, T.p(0.0, 0.0, 1.0)))
	# An inactive scale has no say: generation 1 has only aggressive/defensive.
	var gen1 := Personality.new(1, 0.0, 1.0, 0.0)
	assert_float(w.weight(IntentWeights.HEAL, gen1)).is_equal(w.weight(IntentWeights.HEAL, null))
