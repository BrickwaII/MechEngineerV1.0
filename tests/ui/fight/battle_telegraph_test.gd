extends GdUnitTestSuite
## The battle screen's intent telegraphs, revision marks, personality tags and
## choice preview, driven through the screen's own code path, headless.

const Helpers := preload("res://tests/ui/fight/fight_ui_helpers.gd")
const T := preload("res://tests/fight/intent/intent_test_helpers.gd")

var _runner: GdUnitSceneRunner
var _screen: BattleScreen


func _start(screen: BattleScreen) -> void:
	_screen = screen
	_runner = scene_runner(auto_free(_screen))
	await _runner.simulate_frames(1)
	await _enemies_done()


func _enemies_done() -> void:
	var guard := 0
	while _screen.handler.is_enemy_turn() and guard < 200:
		await _runner.simulate_frames(1)
		guard += 1


func _hover(unit_id: String) -> void:
	_screen.unit_panels[unit_id].hovered.emit(unit_id, true)


func test_each_enemy_panel_shows_its_intent_in_words() -> void:
	await _start(Helpers.screen())
	for c in _screen.fight.living(Combatant.Side.ENEMY):
		var intent := _screen.telegraph.intent_of(c.id)
		assert_object(intent).is_not_null()
		var text: String = _screen.unit_panels[c.id].intent_label.text
		assert_str(text).is_equal("Intent: " + _screen.telegraph.intent_text(_screen.fight, c.id))
		assert_str(text).contains(_screen.fight.tuning.skill(intent.skill_id()).display_name)
		assert_str(text).contains(_screen.fight.combatant(intent.target_id()).display_name)


func test_intents_refresh_after_every_action() -> void:
	await _start(Helpers.screen())
	for turn in 4:
		Helpers.play_turn_by_mouse(_screen)
		await _enemies_done()
		if _screen.fight.is_over():
			break
		var fresh := _screen.telegraph.planner.plan_all(_screen.fight)
		for id in fresh:
			assert_bool(fresh[id].same_as(_screen.telegraph.intent_of(id))).is_true()


func test_every_panel_shows_a_personality_tag() -> void:
	await _start(Helpers.screen())
	for c in _screen.fight.combatants:
		var tag: String = _screen.unit_panels[c.id].tag_label.text
		assert_str(tag).is_not_empty()
		assert_str(tag).is_equal(_screen.telegraph.tag_of(c.id))
	assert_str(_screen.unit_panels["stub_bolt"].tag_label.text).is_equal("aggressive")


func test_enemies_do_what_they_telegraph() -> void:
	await _start(Helpers.healer_screen())
	var played: Array[String] = []
	var promised: Array[String] = []
	_screen.handler.action_resolved.connect(func(actor_id: String, tag: String) -> void:
		var intent := _screen.telegraph.intent_of(actor_id)
		if intent == null:
			return
		played.append(tag)
		var skill := intent.skill_id() if intent.kind != UnitIntent.Kind.WAIT else "wait"
		promised.append("%s:%s" % [actor_id, skill]))
	var turns := 0
	while not _screen.fight.is_over() and turns < 100:
		Helpers.play_turn_by_mouse(_screen)
		await _enemies_done()
		turns += 1
	assert_bool(_screen.fight.is_over()).is_true()
	assert_array(played).is_not_empty()
	assert_array(played).is_equal(promised)
	assert_str(_screen.fight.log_text()).not_contains("policy refused")


func test_a_revision_marks_the_panel_for_one_turn() -> void:
	await _start(Helpers.healer_screen())
	var medic = _screen.unit_panels["warden_mech#2"]
	assert_bool(medic.intent_changed).is_false()
	assert_bool(medic.change_label.visible).is_false()
	assert_str(medic.intent_label.text).starts_with("Intent: Strike -> Bolt")
	# Bolt hits the first Warden; the second switches to repairing it.
	_screen.skill_buttons["heavy_strike"].pressed.emit()
	Helpers.click(_screen.unit_panels["warden_mech#1"])
	assert_bool(_screen.telegraph.is_marked("warden_mech#2")).is_true()
	assert_bool(medic.intent_changed).is_true()
	assert_bool(medic.change_label.visible).is_true()
	assert_str(medic.change_label.text).starts_with("changed: Warden Mech 1 hp 40 -> ")
	assert_str(medic.intent_label.text).starts_with("Intent: Repair -> Warden Mech 1 (+")
	assert_that(medic._style.border_color).is_equal(FeelData.color("changed"))
	# The mark goes once the next bot action resolves, unless that revises it again.
	await _enemies_done()
	_screen.skill_buttons["strike"].pressed.emit()
	Helpers.click(_screen.unit_panels["warden_mech#1"])
	if not _screen.telegraph.is_marked("warden_mech#2"):
		assert_bool(medic.intent_changed).is_false()
		assert_bool(medic.change_label.visible).is_false()
	else:
		var r := _screen.telegraph.marks["warden_mech#2"]
		assert_int(r.action_count).is_equal(_screen.fight.action_count)


func test_the_preview_never_changes_the_fight() -> void:
	await _start(Helpers.screen())
	var before := T.snapshot(_screen.fight)
	var intents_before := str(_screen.telegraph.tracker.current)
	var revisions_before := _screen.telegraph.tracker.history.size()
	for skill_id in _screen.skill_buttons:
		if not _screen.handler.skill_problem(skill_id).is_empty():
			continue
		_screen.skill_buttons[skill_id].pressed.emit()
		for c in _screen.fight.combatants:
			_hover(c.id)
			_screen.unit_panels[c.id].hovered.emit(c.id, false)
		_screen.cancel_button.pressed.emit()
	assert_str(T.snapshot(_screen.fight)).is_equal(before)
	assert_str(str(_screen.telegraph.tracker.current)).is_equal(intents_before)
	assert_int(_screen.telegraph.tracker.history.size()).is_equal(revisions_before)


func test_pointing_at_a_target_shows_the_preview_in_the_box_and_on_the_panels() -> void:
	await _start(Helpers.healer_screen())
	assert_str(_screen.preview_label.text).contains("Choose a skill")
	_screen.skill_buttons["heavy_strike"].pressed.emit()
	assert_str(_screen.preview_label.text).contains("point at a target")
	_hover("warden_mech#1")
	var choice := _screen.shown_preview
	assert_object(choice).is_not_null()
	var effect := choice.effect_on("warden_mech#1")
	assert_object(effect).is_not_null()
	var target = _screen.unit_panels["warden_mech#1"]
	assert_bool(target.preview_label.visible).is_true()
	# The target's own line first; a Warden hit also means to repair itself.
	assert_str(target.preview_label.text).starts_with(FightTelegraph.effect_text(effect))
	assert_str(_screen.preview_label.text).contains("Warden Mech 1 " + FightTelegraph.effect_text(effect))
	var medic = _screen.unit_panels["warden_mech#2"]
	assert_str(medic.preview_label.text).starts_with("would switch to Repair -> Warden Mech 1")
	assert_str(_screen.preview_label.text).contains("Warden Mech 2 would switch to Repair")
	# Pointing away clears it.
	target.hovered.emit("warden_mech#1", false)
	assert_object(_screen.shown_preview).is_null()
	assert_bool(target.preview_label.visible).is_false()


func test_a_downing_choice_says_who_goes_down() -> void:
	await _start(Helpers.healer_screen())
	_screen.fight.combatant("warden_mech#1").hp = 3
	_screen.skill_buttons["strike"].pressed.emit()
	_hover("warden_mech#1")
	# A unit that goes down shows no intent change.
	assert_str(_screen.unit_panels["warden_mech#1"].preview_label.text).is_equal("-3 (3 -> 0) DOWN")
	assert_str(_screen.preview_label.text).contains("goes down: Warden Mech 1")


func test_unknown_values_show_a_question_mark_in_the_scene() -> void:
	await _start(Helpers.healer_screen())
	_screen.telegraph.preview.rules.random_skills.append("strike")
	_screen.skill_buttons["strike"].pressed.emit()
	_hover("warden_mech#1")
	assert_str(_screen.unit_panels["warden_mech#1"].preview_label.text).is_equal("-? (40 -> ?)\nintent after: ?")
	assert_str(_screen.unit_panels["warden_mech#2"].preview_label.text).is_equal("intent after: ?")
	assert_str(_screen.preview_label.text).contains("enemy intents: ?")
