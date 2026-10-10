extends GdUnitTestSuite
## Intent is recomputed when the fight changes, and each change is recorded.

const T := preload("res://tests/fight/intent/intent_test_helpers.gd")


func _hit_grunt(f: Fight) -> void:
	assert_str(f.advance().id).is_equal("bolt")
	assert_str(f.submit(FightAction.use("strike", "grunt#1"))).is_empty()


func test_the_first_refresh_plans_without_revisions() -> void:
	var f := T.healer_fight()
	var tracker := IntentTracker.new(T.healer_planner())
	assert_array(tracker.refresh(f)).is_empty()
	assert_array(tracker.current.keys()).contains_exactly(["medic#1", "grunt#1"])
	assert_array(tracker.history).is_empty()


func test_a_healer_planning_an_attack_switches_to_healing_after_an_ally_is_hit() -> void:
	var f := T.healer_fight()
	var tracker := IntentTracker.new(T.healer_planner())
	tracker.refresh(f)
	var planned := tracker.intent_of("medic#1")
	assert_int(planned.kind).is_equal(UnitIntent.Kind.ATTACK)
	assert_str(planned.target_id()).is_equal("bolt")

	_hit_grunt(f)  # Bolt: 12 attack against 2 defense, 11 damage.
	var revisions := tracker.refresh(f)

	assert_int(revisions.size()).is_equal(1)
	var r := revisions[0]
	assert_str(r.unit_id).is_equal("medic#1")
	assert_object(r.old_intent).is_same(planned)
	assert_int(r.new_intent.kind).is_equal(UnitIntent.Kind.HEAL)
	assert_str(r.new_intent.skill_id()).is_equal("repair")
	assert_str(r.new_intent.target_id()).is_equal("grunt#1")
	assert_int(r.new_intent.amount).is_equal(8)
	assert_str(r.reason).contains("Grunt 1 hp 30 -> 19")
	assert_int(r.action_count).is_equal(1)
	assert_object(tracker.intent_of("medic#1")).is_same(r.new_intent)
	assert_array(tracker.history).contains_exactly([r])


func test_revisions_are_announced() -> void:
	var f := T.healer_fight()
	var tracker := IntentTracker.new(T.healer_planner())
	var seen: Array[IntentRevision] = []
	tracker.intent_revised.connect(func(r: IntentRevision) -> void: seen.append(r))
	tracker.refresh(f)
	_hit_grunt(f)
	tracker.refresh(f)
	assert_int(seen.size()).is_equal(1)
	assert_str(seen[0].unit_id).is_equal("medic#1")


func test_no_change_means_no_revision() -> void:
	var f := T.healer_fight()
	var tracker := IntentTracker.new(T.healer_planner())
	tracker.refresh(f)
	assert_array(tracker.refresh(f)).is_empty()
	assert_array(tracker.history).is_empty()


func test_a_unit_that_goes_down_loses_its_intent() -> void:
	var f := T.healer_fight()
	var tracker := IntentTracker.new(T.healer_planner())
	tracker.refresh(f)
	f.combatant("grunt#1").hp = 0
	var revisions := tracker.refresh(f)
	var grunt: Array = revisions.filter(func(r: IntentRevision) -> bool: return r.unit_id == "grunt#1")
	assert_int(grunt.size()).is_equal(1)
	assert_object(grunt[0].new_intent).is_null()
	assert_str(grunt[0].reason).contains("(down)")
	assert_object(tracker.intent_of("grunt#1")).is_null()


func test_a_given_reason_is_kept() -> void:
	var f := T.healer_fight()
	var tracker := IntentTracker.new(T.healer_planner())
	tracker.refresh(f)
	_hit_grunt(f)
	assert_str(tracker.refresh(f, "ally hit")[0].reason).is_equal("ally hit")


func test_refreshing_does_not_change_the_fight() -> void:
	var f := T.healer_fight()
	var tracker := IntentTracker.new(T.healer_planner())
	tracker.refresh(f)
	_hit_grunt(f)
	var before := T.snapshot(f)
	tracker.refresh(f)
	assert_str(T.snapshot(f)).is_equal(before)
