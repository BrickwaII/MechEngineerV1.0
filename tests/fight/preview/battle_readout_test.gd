extends GdUnitTestSuite
## BattleReadout and ArrowBadge: the numbers the battle screen draws on its
## arrows, worked out without changing the fight.

const T := preload("res://tests/fight/intent/intent_test_helpers.gd")


func _ready_fight() -> Fight:
	var f := T.healer_fight()
	assert_str(f.advance().id).is_equal("bolt")
	return f


func test_badge_text_by_kind() -> void:
	assert_str(ArrowBadge.new("a", "b", ArrowBadge.ATTACK, "strike", PreviewValue.of(6)).text()).is_equal("6")
	assert_str(ArrowBadge.new("a", "b", ArrowBadge.HEAL, "repair", PreviewValue.of(5)).text()).is_equal("+5")
	assert_str(ArrowBadge.new("a", "b", ArrowBadge.GUARD, "brace", PreviewValue.of(50)).text()).is_equal("50%")
	assert_str(ArrowBadge.new("a", "b", ArrowBadge.ATTACK, "x", PreviewValue.unknown()).text()).is_equal("?")


func test_intent_badges_carry_the_intent_amount_and_target() -> void:
	var f := _ready_fight()
	var planner := T.healer_planner()
	var intents := planner.plan_all(f)
	var badges := BattleReadout.intent_badges(f, intents)
	assert_int(badges.size()).is_equal(intents.size())
	for b in badges:
		var intent: UnitIntent = intents[b.from_id]
		assert_str(b.to_id).is_equal(intent.target_id())
		assert_int(b.amount.value).is_equal(mini(intent.amount, f.combatant(b.to_id).hp))
		assert_bool(b.knocks_out).is_false()


func test_a_hit_that_downs_its_target_is_marked_ko_and_capped_at_the_hp_left() -> void:
	var f := _ready_fight()
	var bolt := f.combatant("bolt")
	bolt.hp = 2
	var grunt := f.combatant("grunt#1")
	var b := BattleReadout.hit_badge(grunt, bolt, grunt.skill("strike"), ArrowBadge.ATTACK, 0, f.tuning)
	assert_int(b.amount.value).is_equal(2)
	assert_bool(b.knocks_out).is_true()


func test_random_skills_show_unknown_badges() -> void:
	var f := _ready_fight()
	var rules := PreviewRules.new()
	rules.random_skills.append("strike")
	for b in BattleReadout.intent_badges(f, T.healer_planner().plan_all(f), rules):
		if b.skill_id == "strike":
			assert_bool(b.amount.is_unknown()).is_true()
			assert_bool(b.knocks_out).is_false()


func test_choice_badges_follow_the_preview() -> void:
	var f := _ready_fight()
	f.combatant("grunt#1").hp = 5
	var preview := FightPreview.new(T.healer_planner(), PreviewRules.new())
	var action := FightAction.use("strike", "grunt#1")
	var badges := BattleReadout.choice_badges(f, action, preview.preview_choice(f, action))
	assert_int(badges.size()).is_equal(1)
	assert_str(badges[0].from_id).is_equal("bolt")
	assert_str(badges[0].to_id).is_equal("grunt#1")
	assert_str(badges[0].text()).is_equal("5")
	assert_bool(badges[0].knocks_out).is_true()


func test_compare_marks_new_and_changed_arrows() -> void:
	var old: Array[ArrowBadge] = [
		ArrowBadge.new("e1", "a", ArrowBadge.ATTACK, "strike", PreviewValue.of(6)),
		ArrowBadge.new("e2", "a", ArrowBadge.ATTACK, "strike", PreviewValue.of(4)),
	]
	var after: Array[ArrowBadge] = [
		ArrowBadge.new("e1", "a", ArrowBadge.ATTACK, "strike", PreviewValue.of(3)),
		ArrowBadge.new("e2", "e1", ArrowBadge.HEAL, "repair", PreviewValue.of(5)),
	]
	BattleReadout.compare(old, after)
	assert_bool(after[0].changed).is_true()
	assert_str(after[0].old_amount.text()).is_equal("6")
	assert_bool(after[1].changed).is_true()
	assert_object(after[1].old_amount).is_null()
	var same: Array[ArrowBadge] = [ArrowBadge.new("e1", "a", ArrowBadge.ATTACK, "strike", PreviewValue.of(6))]
	BattleReadout.compare(old, same)
	assert_bool(same[0].changed).is_false()


func test_energy_after_pays_the_cost() -> void:
	var f := _ready_fight()
	var bolt := f.combatant("bolt")
	var heavy := bolt.skill("heavy_strike")
	@warning_ignore("integer_division")
	assert_int(BattleReadout.energy_after(bolt, heavy)).is_equal((bolt.energy_milli - heavy.energy_cost_milli()) / Combatant.MILLI)


func test_the_preview_carries_energy_order_and_next_intents() -> void:
	var f := _ready_fight()
	var preview := FightPreview.new(T.healer_planner(), PreviewRules.new())
	var action := FightAction.use("heavy_strike", "medic#1")
	var choice := preview.preview_choice(f, action)
	assert_bool(choice.energy_after.has("bolt")).is_true()
	assert_int(choice.order_after.size()).is_equal(preview.order_length)
	assert_object(choice.fight_after).is_not_null()
	var before := T.snapshot(f)
	f.submit(action)
	assert_int(f.combatant("bolt").energy()).is_equal(choice.energy_after["bolt"])
	f.advance()
	assert_str(str(T.healer_planner().plan_all(f))).is_equal(str(choice.intents_after))
	assert_str(before).is_not_equal(T.snapshot(f))
