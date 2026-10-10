extends GdUnitTestSuite
## FightPreview.units(): a read-only view of each unit's intent and personality.

const T := preload("res://tests/fight/intent/intent_test_helpers.gd")


func _preview() -> FightPreview:
	return FightPreview.new(T.healer_planner(), PreviewRules.new())


func test_one_entry_per_living_unit_with_intent_and_personality_tag() -> void:
	var f := T.healer_fight()
	var units := _preview().units(f)
	assert_array(units.map(func(u: UnitPreview) -> String: return u.unit_id)).contains_exactly(["bolt", "medic#1", "grunt#1"])
	var bolt := units[0]
	assert_bool(bolt.has_intent()).is_false()
	assert_str(bolt.personality_tag).is_equal("test")  # from the squad summary
	var medic := units[1]
	assert_str(medic.personality_tag).is_equal("supportive")
	assert_str(medic.intent.skill_id()).is_equal("strike")
	assert_str(medic.amount.text()).is_equal("6")
	assert_str(medic.intent_text()).is_equal("strike on bolt: 6")
	assert_str(units[2].personality_tag).is_equal("aggressive")


func test_downed_units_are_left_out() -> void:
	var f := T.healer_fight()
	f.combatant("grunt#1").hp = 0
	assert_int(_preview().units(f).size()).is_equal(2)


func test_uses_the_intents_it_is_given() -> void:
	var f := T.healer_fight()
	var tracker := IntentTracker.new(T.healer_planner())
	tracker.refresh(f)
	var units := _preview().units(f, tracker.current)
	assert_object(units[1].intent).is_same(tracker.intent_of("medic#1"))


func test_building_a_preview_never_changes_the_fight() -> void:
	var f := T.healer_fight()
	var preview := _preview()
	for step in 4:
		var actor := f.advance()
		var before := T.snapshot(f)
		preview.units(f)
		preview.preview_choice(f, FightAction.use("strike", f.opponents_of(actor)[0].id))
		preview.preview_choice(f, FightAction.use("overload", f.opponents_of(actor)[0].id))
		preview.preview_choice(f, FightAction.wait_for("overload"))
		assert_str(T.snapshot(f)).is_equal(before)
		f.submit(FightAction.use("strike", f.opponents_of(actor)[0].id))


func test_the_default_rules_load_and_predict_everything() -> void:
	var rules := PreviewRules.load_default()
	assert_object(rules).is_not_null()
	for id: String in CombatTuning.load_default().skills:
		assert_bool(rules.is_random(id)).is_false()
