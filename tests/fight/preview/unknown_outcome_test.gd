extends GdUnitTestSuite
## Outcomes that depend on randomness are reported as unknown, never as a
## made-up number.

const T := preload("res://tests/fight/intent/intent_test_helpers.gd")


func _random(skills: Array) -> PreviewRules:
	return PreviewRules.from_dict({"random_skills": skills})


func test_an_unknown_value_is_distinct_from_every_number() -> void:
	var unknown := PreviewValue.unknown()
	assert_bool(unknown.is_unknown()).is_true()
	assert_str(unknown.text()).is_equal(PreviewValue.UNKNOWN_TEXT)
	assert_str(unknown.text()).is_equal("?")
	for n in [0, 1, -1]:
		assert_bool(unknown.equals(PreviewValue.of(n))).is_false()
	assert_bool(unknown.equals(PreviewValue.unknown())).is_true()
	assert_str(PreviewValue.of(7).text()).is_equal("7")
	assert_bool(PreviewValue.of(7).equals(PreviewValue.of(7))).is_true()


func test_rules_mark_only_listed_skills_random() -> void:
	var rules := _random(["overload"])
	assert_bool(rules.value_for("overload", 22).is_unknown()).is_true()
	assert_str(rules.value_for("strike", 10).text()).is_equal("10")


func test_a_random_choice_reports_unknown_damage_and_unknown_intent_changes() -> void:
	var f := T.healer_fight()
	f.advance()
	var before := T.snapshot(f)
	var preview := FightPreview.new(T.healer_planner(), _random(["heavy_strike"]))
	var p := preview.preview_choice(f, FightAction.use("heavy_strike", "grunt#1"))
	assert_bool(p.is_allowed()).is_true()
	var e := p.effect_on("grunt#1")
	assert_bool(e.damage.is_unknown()).is_true()
	assert_bool(e.hp_after.is_unknown()).is_true()
	assert_str(e.damage.text()).is_equal("?")
	assert_bool(e.would_go_down()).is_false()
	assert_bool(p.intent_changes_known).is_false()
	assert_array(p.intent_changes).is_empty()
	assert_str(T.snapshot(f)).is_equal(before)
	# A deterministic skill in the same fight is still a number.
	var known := preview.preview_choice(f, FightAction.use("strike", "grunt#1"))
	assert_str(known.effect_on("grunt#1").damage.text()).is_equal("11")
	assert_bool(known.intent_changes_known).is_true()


func test_an_enemy_intent_with_a_random_skill_shows_an_unknown_amount() -> void:
	var f := T.healer_fight()
	var units := FightPreview.new(T.healer_planner(), _random(["strike"])).units(f)
	var medic := units[1]
	assert_str(medic.intent.skill_id()).is_equal("strike")
	assert_bool(medic.amount.is_unknown()).is_true()
	assert_str(medic.intent_text()).is_equal("strike on bolt: ?")
