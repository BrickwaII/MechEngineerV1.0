extends GdUnitTestSuite
## IntentFightPolicy: headless fights play enemies by their intent.

const H := preload("res://tests/fight/fight_test_helpers.gd")
const T := preload("res://tests/fight/intent/intent_test_helpers.gd")


func _request(level: int) -> FightRequest:
	var squad: Array[SquadMemberSummary] = [
		H.member("ace", H.stats(40, 9, 3, 6, 10)),
		H.member("bea", H.stats(40, 8, 4, 5, 12)),
	]
	return H.request(squad, level)


func test_plays_the_planned_intent_when_the_fight_allows_it() -> void:
	var f := T.fight(
		[{"id": "bolt", "stats": T.stats(100, 10, 0, 1, 10)}],
		[{"id": "foe#1", "stats": T.stats(100, 10, 0, 20, 10), "skills": ["strike", "heavy_strike"]}])
	var planner := T.planner({"foe#1": T.p(-1.0)})
	var actor := f.advance()
	assert_str(actor.id).is_equal("foe#1")
	var action := IntentFightPolicy.new(planner).choose(f, actor, RandomNumberGenerator.new())
	assert_str(str(action)).is_equal(str(planner.plan(f, actor).action))
	assert_str(action.skill_id).is_equal("heavy_strike")


func test_falls_back_to_a_legal_option_when_the_intent_is_a_heal() -> void:
	# The combat core resolves attacks only, so a planned heal cannot be played yet.
	var f := T.healer_fight()
	f.combatant("grunt#1").hp = 10
	f.combatant("bolt").stats = T.stats(60, 12, 4, 1, 10)
	f.combatant("bolt").charge_per_tick = 1
	var planner := T.healer_planner()
	var actor := f.advance()
	assert_str(actor.id).is_equal("medic#1")
	assert_int(planner.plan(f, actor).kind).is_equal(UnitIntent.Kind.HEAL)
	var action := IntentFightPolicy.new(planner).choose(f, actor, RandomNumberGenerator.new())
	assert_str(f.check_action(action)).is_empty()
	assert_str(action.target_id).is_equal("bolt")


func test_headless_fights_with_intent_finish_and_replay_exactly() -> void:
	for level in [0, 2, 5]:
		var a := HeadlessFightRunner.run(_request(level), 7, SimpleFightPolicy.new(), IntentFightPolicy.new())
		var b := HeadlessFightRunner.run(_request(level), 7, SimpleFightPolicy.new(), IntentFightPolicy.new())
		assert_bool(a.is_over()).is_true()
		assert_str(a.log_text()).is_equal(b.log_text())
		assert_str(a.log_text()).not_contains("policy refused")
