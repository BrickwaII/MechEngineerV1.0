extends GdUnitTestSuite
## Plated (combat rework S5): four pips of plating on a high-Defense enemy.
## Breaking it (multi-hits) and paying the Stagger off with a heavy hit beats
## greedy play (Heavy Strike every turn).

const A := preload("res://tests/fight/archetypes/archetype_test_helpers.gd")


func test_the_shipped_plated_archetype_gives_four_pips_and_plans_freely() -> void:
	var fight := A.plated_fight()
	var plated := fight.combatant("plated#1")
	assert_str(plated.archetype.id).is_equal("plated")
	assert_int(plated.plating).is_equal(4)
	assert_int(plated.max_plating).is_equal(4)
	assert_array(plated.archetype.intent_pattern).is_empty()
	# A plan-only pattern narrows nothing: the same intent as without one.
	var free := fight.planner().rank_unpatterned(fight, plated)
	assert_bool(fight.planner().plan(fight, plated).same_as(free[0])).is_true()


func test_breaking_the_plating_beats_greedy_heavy_hits() -> void:
	var greedy_fight := A.plated_fight()
	var greedy_events := A.record(greedy_fight)
	A.play(greedy_fight, SimpleFightPolicy.new())
	var answer_fight := A.plated_fight()
	var answer_events := A.record(answer_fight)
	A.play(answer_fight, A.AnswerPolicy.new())
	assert_bool(A.won(answer_fight)).is_true()
	assert_int(A.squad_hp_lost(answer_fight)).is_less(A.squad_hp_lost(greedy_fight))
	assert_int(answer_fight.action_count).is_less(greedy_fight.action_count)
	# The answer Staggers it sooner, and cashes the Stagger with a payoff.
	var first_stagger := func(events: Array[FightEvent]) -> int:
		for e in events:
			if e.kind == FightEvent.Kind.STAGGER:
				return e.action_index
		return 1 << 30
	assert_int(first_stagger.call(answer_events)).is_less(first_stagger.call(greedy_events))
	assert_bool(A.of_kind(answer_events, FightEvent.Kind.HIT).any(
		func(e: FightEvent) -> bool: return e.payoff_bonus_percent > 0)).is_true()


func test_a_staggered_plated_enemy_announces_losing_and_regaining_its_intent() -> void:
	var fight := A.plated_fight()
	var events := A.record(fight)
	A.play(fight, A.AnswerPolicy.new())
	var changes := A.of_kind(events, FightEvent.Kind.INTENT_CHANGED)
	assert_bool(changes.any(func(e: FightEvent) -> bool: return e.reason == "staggered" and e.new_intent == null)).is_true()
