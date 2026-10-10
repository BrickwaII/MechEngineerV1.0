extends GdUnitTestSuite
## FightPreview.preview_choice(): what a pending player action would do,
## without doing it.

const T := preload("res://tests/fight/intent/intent_test_helpers.gd")


func _ready_fight() -> Fight:
	var f := T.healer_fight()
	assert_str(f.advance().id).is_equal("bolt")
	return f


func _preview() -> FightPreview:
	return FightPreview.new(T.healer_planner(), PreviewRules.new())


func test_reports_damage_to_the_target_only() -> void:
	var f := _ready_fight()
	var p := _preview().preview_choice(f, FightAction.use("strike", "grunt#1"))
	assert_bool(p.is_allowed()).is_true()
	assert_int(p.effects.size()).is_equal(1)
	var e := p.effect_on("grunt#1")
	assert_int(e.hp_before).is_equal(30)
	assert_str(e.damage.text()).is_equal("11")
	assert_str(e.hp_after.text()).is_equal("19")
	assert_bool(e.would_go_down()).is_false()


func test_damage_matches_the_real_submit() -> void:
	var f := _ready_fight()
	var action := FightAction.use("heavy_strike", "medic#1")
	var p := _preview().preview_choice(f, action)
	f.submit(action)
	assert_int(p.effect_on("medic#1").hp_after.value).is_equal(f.combatant("medic#1").hp)


func test_reports_which_enemy_intents_would_change() -> void:
	var f := _ready_fight()
	var p := _preview().preview_choice(f, FightAction.use("strike", "grunt#1"))
	assert_bool(p.intent_changes_known).is_true()
	assert_int(p.intent_changes.size()).is_equal(1)
	var r := p.change_for("medic#1")
	assert_int(r.old_intent.kind).is_equal(UnitIntent.Kind.ATTACK)
	assert_int(r.new_intent.kind).is_equal(UnitIntent.Kind.HEAL)
	assert_str(r.new_intent.target_id()).is_equal("grunt#1")
	assert_str(r.reason).contains("strike on grunt#1")


func test_a_finishing_blow_shows_the_unit_going_down_and_losing_its_intent() -> void:
	var f := _ready_fight()
	f.combatant("grunt#1").hp = 5
	var p := _preview().preview_choice(f, FightAction.use("strike", "grunt#1"))
	assert_str(p.effect_on("grunt#1").hp_after.text()).is_equal("0")
	assert_bool(p.effect_on("grunt#1").would_go_down()).is_true()
	assert_object(p.change_for("grunt#1").new_intent).is_null()


func test_a_refused_choice_reports_why_and_nothing_else() -> void:
	var f := _ready_fight()
	var p := _preview().preview_choice(f, FightAction.use("strike", "bolt"))
	assert_bool(p.is_allowed()).is_false()
	assert_array(p.effects).is_empty()
	assert_array(p.intent_changes).is_empty()


func test_a_wait_deals_no_damage() -> void:
	var f := _ready_fight()
	var p := _preview().preview_choice(f, FightAction.wait_for("overload"))
	assert_bool(p.is_allowed()).is_true()
	assert_array(p.effects).is_empty()
	assert_array(p.intent_changes).is_empty()


func test_previewing_does_not_change_the_fight() -> void:
	var f := _ready_fight()
	var before := T.snapshot(f)
	_preview().preview_choice(f, FightAction.use("strike", "grunt#1"))
	assert_str(T.snapshot(f)).is_equal(before)
	# And the fight still plays on from where it was.
	assert_str(f.submit(FightAction.use("strike", "grunt#1"))).is_empty()
	assert_int(f.combatant("grunt#1").hp).is_equal(19)
