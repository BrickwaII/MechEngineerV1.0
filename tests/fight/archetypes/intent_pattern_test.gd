extends GdUnitTestSuite
## Archetype intent patterns and the fight's INTENT_CHANGED events (combat
## rework S5): pattern steps narrow the planner's options, and the fight
## announces archetype enemies' intents as they change. Enemies without an
## archetype are planned and fought exactly as before.

const A := preload("res://tests/fight/archetypes/archetype_test_helpers.gd")
const H := preload("res://tests/fight/fight_test_helpers.gd")


static func _unit(fight: Fight, pattern: Array) -> Combatant:
	var unit := fight.combatant("charger#1")
	unit.archetype = EnemyArchetype.from_dict("test", {"name": "Test", "intent_pattern": pattern})
	unit.pattern_step = 0
	return unit


func test_an_action_step_keeps_only_that_actions_options() -> void:
	var fight := A.charger_fight()
	var unit := _unit(fight, ["ram"])
	unit.energy_milli = unit.max_energy_milli
	for o in fight.planner().rank(fight, unit):
		assert_str(o.skill_id()).is_equal("ram")
		assert_int(o.kind).is_equal(UnitIntent.Kind.ATTACK)


func test_an_unaffordable_action_step_waits_for_that_action_and_stays_on_the_step() -> void:
	var fight := A.charger_fight()
	var unit := _unit(fight, ["ram", "strike"])
	unit.energy_milli = 0
	var intent := fight.planner().plan(fight, unit)
	assert_int(intent.kind).is_equal(UnitIntent.Kind.WAIT)
	assert_bool(intent.wind_up).is_false()
	assert_str(intent.skill_id()).is_equal("ram")
	ArchetypeRules.after_decision(fight, unit, intent.action)
	assert_int(unit.pattern_step).is_equal(0)
	assert_object(unit.committed).is_null()


func test_a_wind_up_step_offers_wind_ups_of_the_next_action() -> void:
	var fight := A.charger_fight()
	var unit := _unit(fight, ["wind_up", "ram"])
	var ranked := fight.planner().rank(fight, unit)
	assert_array(ranked).is_not_empty()
	for o in ranked:
		assert_int(o.kind).is_equal(UnitIntent.Kind.WAIT)
		assert_bool(o.wind_up).is_true()
		assert_str(o.skill_id()).is_equal("ram")
		assert_str(o.action.target_id).is_not_empty()


func test_a_wind_up_before_a_plan_step_winds_up_the_best_attack() -> void:
	var fight := A.charger_fight()
	var unit := _unit(fight, ["wind_up", "plan"])
	var intent := fight.planner().plan(fight, unit)
	assert_bool(intent.wind_up).is_true()
	assert_str(intent.skill_id()).is_not_empty()


func test_a_step_naming_an_action_the_unit_lacks_plans_freely() -> void:
	var fight := A.charger_fight()
	var unit := _unit(fight, ["overload"])
	var free := fight.planner().rank_unpatterned(fight, unit)
	assert_bool(fight.planner().plan(fight, unit).same_as(free[0])).is_true()


func test_step_at_and_action_after_wrap_around_the_pattern() -> void:
	var a := EnemyArchetype.from_dict("c", {"intent_pattern": ["strike", "wind_up", "ram"]})
	assert_str(a.step_at(0)).is_equal("strike")
	assert_str(a.step_at(4)).is_equal("wind_up")
	assert_str(a.action_after(1)).is_equal("ram")
	assert_str(a.action_after(2)).is_equal("strike")
	assert_str(EnemyArchetype.from_dict("p", {}).step_at(7)).is_equal(EnemyArchetype.STEP_PLAN)
	assert_str(EnemyArchetype.from_dict("w", {"intent_pattern": ["wind_up", "plan"]}).action_after(0)).is_empty()


func test_the_opening_plan_is_recorded_without_events() -> void:
	var fight := A.charger_fight()
	assert_array(fight.last_events).is_empty()
	assert_object(fight.combatant("charger#1").intent).is_not_null()
	# Enemies without an archetype get no fight-held intent.
	assert_object(fight.combatant("grunt#1").intent).is_null()


func test_intent_changed_is_raised_only_for_archetype_enemies() -> void:
	var fight := A.charger_fight()
	var events := A.record(fight)
	A.play(fight, SimpleFightPolicy.new())
	var changed := A.of_kind(events, FightEvent.Kind.INTENT_CHANGED)
	assert_array(changed).is_not_empty()
	for e in changed:
		assert_str(e.actor_id).is_equal("charger#1")
		assert_str(e.reason).is_not_empty()
		assert_bool(e.old_intent == null or e.new_intent == null or not e.old_intent.same_as(e.new_intent)).is_true()
	# Each event says what the intent became; the next starts from it.
	for i in range(1, changed.size()):
		var previous := changed[i - 1].new_intent
		var old := changed[i].old_intent
		assert_bool((previous == null and old == null) or (previous != null and previous.same_as(old))).is_true()


func test_a_fight_without_archetypes_raises_no_intent_events_and_plans_nothing() -> void:
	var fight := H.duel(H.stats(50, 5, 0, 11, 10), H.stats(50, 3, 0, 3, 10))
	var events := A.record(fight)
	var enemy_policy := IntentFightPolicy.new()
	var actor := fight.advance()
	while actor != null:
		fight.submit((SimpleFightPolicy.new() if actor.side == Combatant.Side.PLAYER else enemy_policy).choose(fight, actor, null))
		actor = fight.advance()
	assert_bool(fight.is_over()).is_true()
	assert_array(A.of_kind(events, FightEvent.Kind.INTENT_CHANGED)).is_empty()
	assert_object(fight.intent_planner).is_null()


func test_a_preview_copy_keeps_the_archetype_state_and_leaves_the_fight_alone() -> void:
	var fight := A.charger_fight()
	var charger := fight.combatant("charger#1")
	charger.pattern_step = 1
	charger.growth = 2
	charger.telegraph_wait = 1
	charger.committed = UnitIntent.new(charger.id, UnitIntent.Kind.ATTACK, FightAction.use("ram", "rook"), 20)
	fight._refresh_intents({}, true)
	var copy := FightCopy.of(fight)
	var c := copy.combatant("charger#1")
	assert_object(c.archetype).is_same(charger.archetype)
	assert_int(c.pattern_step).is_equal(1)
	assert_int(c.growth).is_equal(2)
	assert_int(c.telegraph_wait).is_equal(1)
	assert_object(c.committed).is_same(charger.committed)
	assert_object(c.intent).is_same(charger.intent)
	assert_object(c.base_stats).is_same(charger.base_stats)
	assert_object(copy.intent_planner).is_same(fight.intent_planner)
	c.committed = null
	c.pattern_step = 2
	assert_object(charger.committed).is_not_null()
	assert_int(charger.pattern_step).is_equal(1)
