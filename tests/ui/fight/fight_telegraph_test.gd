extends GdUnitTestSuite
## FightTelegraph, headless: intents in words, revision marks, personality
## tags and the choice preview. None of it may change the fight.
const Legacy := preload("res://tests/fight/legacy_switches.gd")

const T := preload("res://tests/fight/intent/intent_test_helpers.gd")
const Helpers := preload("res://tests/ui/fight/fight_ui_helpers.gd")


func _healer() -> Array:
	var f := T.healer_fight()
	return [f, FightTelegraph.new(f, T.healer_planner())]


func _hit_grunt(f: Fight, telegraph: FightTelegraph) -> void:
	var bolt := f.advance()
	assert_str(bolt.id).is_equal("bolt")
	assert_str(f.submit(FightAction.use("strike", "grunt#1"))).is_empty()
	f.advance()
	telegraph.after_action(f, bolt)


func test_every_living_enemy_has_an_intent_in_words() -> void:
	var pair := _healer()
	var f: Fight = pair[0]
	var telegraph: FightTelegraph = pair[1]
	assert_str(telegraph.intent_text(f, "medic#1")).is_equal("Strike -> Bolt (6)")
	assert_str(telegraph.intent_text(f, "grunt#1")).is_equal("Strike -> Bolt (4)")
	assert_str(telegraph.intent_text(f, "bolt")).is_empty()


func test_a_heal_and_a_wait_read_as_words() -> void:
	var pair := _healer()
	var f: Fight = pair[0]
	var telegraph: FightTelegraph = pair[1]
	var heal := UnitIntent.new("medic#1", UnitIntent.Kind.HEAL, FightAction.use("repair", "grunt#1"), 8)
	assert_str(telegraph.describe_intent(f, heal)).is_equal("Repair -> Grunt 1 (+8)")
	var action := FightAction.wait_for("overload")
	action.target_id = "bolt"
	var wait := UnitIntent.new("grunt#1", UnitIntent.Kind.WAIT, action, 12)
	assert_str(telegraph.describe_intent(f, wait)).is_equal("charging Overload, then -> Bolt (12)")


func test_personality_tags_come_from_the_preview_units() -> void:
	var pair := _healer()
	var f: Fight = pair[0]
	var telegraph: FightTelegraph = pair[1]
	for u in telegraph.preview.units(f, telegraph.tracker.current):
		assert_str(telegraph.tag_of(u.unit_id)).is_equal(u.personality_tag)
	assert_str(telegraph.tag_of("medic#1")).is_equal("supportive")
	assert_str(telegraph.tag_of("bolt")).is_equal("test")


func test_a_healer_switching_to_heal_is_marked_with_the_reason() -> void:
	var pair := _healer()
	var f: Fight = pair[0]
	var telegraph: FightTelegraph = pair[1]
	assert_bool(telegraph.is_marked("medic#1")).is_false()
	_hit_grunt(f, telegraph)
	assert_bool(telegraph.is_marked("medic#1")).is_true()
	assert_str(telegraph.change_text("medic#1")).starts_with("changed: Grunt 1 hp 30 -> ")
	assert_str(telegraph.intent_text(f, "medic#1")).starts_with("Repair -> Grunt 1 (+")


func test_marks_last_until_the_next_bot_action() -> void:
	var pair := _healer()
	var f: Fight = pair[0]
	var telegraph: FightTelegraph = pair[1]
	_hit_grunt(f, telegraph)
	assert_bool(telegraph.is_marked("medic#1")).is_true()
	# Enemy actions in between keep the mark.
	while f.pending_actor.side == Combatant.Side.ENEMY:
		var enemy := f.pending_actor
		f.submit(telegraph.enemy_policy().choose(f, enemy, null))
		f.advance()
		telegraph.after_action(f, enemy)
	var bot := f.pending_actor
	f.submit(FightAction.use("strike", "medic#1"))
	f.advance()
	telegraph.after_action(f, bot)
	for id in telegraph.marks:
		# Only revisions caused by the latest bot action remain.
		assert_int(telegraph.marks[id].action_count).is_equal(f.action_count)


func test_previewing_every_choice_changes_nothing() -> void:
	var pair := _healer()
	var f: Fight = pair[0]
	var telegraph: FightTelegraph = pair[1]
	f.advance()
	var before := T.snapshot(f)
	var plan_before := str(telegraph.tracker.current)
	for skill_id in f.pending_actor.skill_ids:
		for c in f.combatants:
			var action := FightAction.use(skill_id, c.id)
			var choice := telegraph.preview_choice(f, action)
			telegraph.describe_choice(f, action, choice)
	assert_str(T.snapshot(f)).is_equal(before)
	assert_str(str(telegraph.tracker.current)).is_equal(plan_before)
	assert_int(telegraph.tracker.history.size()).is_equal(0)


func test_the_preview_names_damage_downs_and_intent_changes() -> void:
	var pair := _healer()
	var f: Fight = pair[0]
	var telegraph: FightTelegraph = pair[1]
	f.combatant("grunt#1").hp = 5
	f.advance()
	var action := FightAction.use("strike", "grunt#1")
	var choice := telegraph.preview_choice(f, action)
	var text := telegraph.describe_choice(f, action, choice)
	assert_str(text).contains("Grunt 1 -5 (5 -> 0) DOWN")
	assert_str(text).contains("goes down: Grunt 1")
	assert_str(FightTelegraph.effect_text(choice.effect_on("grunt#1"))).is_equal("-5 (5 -> 0) DOWN")
	assert_object(choice.effect_on("medic#1")).is_null()


func test_the_preview_shows_an_intent_change() -> void:
	var pair := _healer()
	var f: Fight = pair[0]
	var telegraph: FightTelegraph = pair[1]
	f.advance()
	var action := FightAction.use("strike", "grunt#1")
	var choice := telegraph.preview_choice(f, action)
	var change := choice.change_for("medic#1")
	assert_object(change).is_not_null()
	assert_str(telegraph.intent_change_text(f, change)).starts_with("would switch to Repair -> Grunt 1")
	assert_str(telegraph.describe_choice(f, action, choice)).contains("Medic 1 would switch to Repair")


func test_unknown_values_show_a_question_mark() -> void:
	var pair := _healer()
	var f: Fight = pair[0]
	var telegraph: FightTelegraph = pair[1]
	telegraph.preview.rules.random_skills.append("strike")
	f.advance()
	var action := FightAction.use("strike", "grunt#1")
	var choice := telegraph.preview_choice(f, action)
	assert_str(FightTelegraph.effect_text(choice.effect_on("grunt#1"))).is_equal("-? (30 -> ?)")
	var text := telegraph.describe_choice(f, action, choice)
	assert_str(text).contains("enemy intents: ?")
	assert_str(telegraph.intent_text(f, "grunt#1")).is_equal("Strike -> Bolt (?)")


func test_a_heal_effect_reads_as_a_gain() -> void:
	var e := UnitEffect.new("grunt#1", "Grunt 1", 10, PreviewValue.of(-8), PreviewValue.of(18))
	assert_str(FightTelegraph.effect_text(e)).is_equal("+8 (10 -> 18)")


func test_a_refused_choice_says_why() -> void:
	var pair := _healer()
	var f: Fight = pair[0]
	var telegraph: FightTelegraph = pair[1]
	f.advance()
	var action := FightAction.use("strike", "bolt")
	var text := telegraph.describe_choice(f, action, telegraph.preview_choice(f, action))
	assert_str(text).contains("not allowed: ")


## These tests' numbers were worked out under the old fight switches.
func before() -> void:
	Legacy.pin()


func after() -> void:
	Legacy.unpin()

