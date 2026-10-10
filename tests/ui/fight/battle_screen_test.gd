extends GdUnitTestSuite
## The battle screen, headless. Clicks go through the panels' own input
## handlers and the buttons' pressed signals, as the mouse would.

const Helpers := preload("res://tests/ui/fight/fight_ui_helpers.gd")

var _runner: GdUnitSceneRunner
var _screen: BattleScreen


func before_test() -> void:
	_screen = Helpers.screen()
	_runner = scene_runner(auto_free(_screen))
	await _runner.simulate_frames(1)
	await _enemies_done()


func _enemies_done() -> void:
	var guard := 0
	while _screen.handler.is_enemy_turn() and guard < 200:
		await _runner.simulate_frames(1)
		guard += 1


func test_one_panel_per_unit_with_live_hp_and_energy() -> void:
	assert_int(_screen.unit_panels.size()).is_equal(_screen.fight.combatants.size())
	for c in _screen.fight.combatants:
		var panel = _screen.unit_panels[c.id]
		assert_int(panel.hp_bar.value).is_equal(c.hp)
		assert_int(panel.hp_bar.max_value).is_equal(c.max_hp)
		assert_int(panel.energy_bar.value).is_equal(c.energy())


func test_panels_update_after_an_action() -> void:
	var target := _screen.fight.living(Combatant.Side.ENEMY)[0]
	var hp_before := target.hp
	_screen.skill_buttons["strike"].pressed.emit()
	Helpers.click(_screen.unit_panels[target.id])
	assert_int(target.hp).is_less(hp_before)
	assert_int(_screen.unit_panels[target.id].hp_bar.value).is_equal(target.hp)


func test_the_timeline_matches_upcoming_and_refreshes_after_each_action() -> void:
	var length := _screen.tuning.timeline_length
	assert_array(_screen.timeline_bar.shown_ids).is_equal(_upcoming_ids(length))
	for turn in 3:
		Helpers.play_turn_by_mouse(_screen)
		assert_array(_screen.timeline_bar.shown_ids).is_equal(_upcoming_ids(length))
		await _enemies_done()
		assert_array(_screen.timeline_bar.shown_ids).is_equal(_upcoming_ids(length))
		if _screen.fight.is_over():
			break


func test_the_acting_bot_is_first_on_the_timeline() -> void:
	assert_str(_screen.timeline_bar.shown_ids[0]).is_equal(_screen.handler.actor().id)


func test_a_whole_fight_is_playable_by_mouse() -> void:
	var results: Array[FightResult] = []
	_screen.fight_finished.connect(func(r: FightResult) -> void: results.append(r))
	var turns := 0
	while not _screen.fight.is_over() and turns < 200:
		Helpers.play_turn_by_mouse(_screen)
		await _enemies_done()
		turns += 1
	assert_bool(_screen.fight.is_over()).is_true()
	assert_int(results.size()).is_equal(1)
	assert_bool(_screen.prompt_label.text in ["VICTORY", "DEFEAT"]).is_true()
	# The same choices through the headless runner give the same fight.
	var runner := HeadlessFightRunner.run(Helpers.request(), Helpers.SEED, SimpleFightPolicy.new(), IntentFightPolicy.new())
	assert_array(_screen.fight.action_tags).is_equal(runner.action_tags)


func test_clicking_another_bot_selects_it_and_right_click_cancels() -> void:
	var actor := _screen.handler.actor()
	var other: Combatant = null
	for c in _screen.fight.living(Combatant.Side.PLAYER):
		if c != actor:
			other = c
	Helpers.click(_screen.unit_panels[other.id])
	assert_str(_screen.handler.selected_bot_id).is_equal(other.id)
	assert_bool(_screen.skill_buttons["strike"].disabled).is_true()
	Helpers.click(_screen.unit_panels[other.id], MOUSE_BUTTON_RIGHT)
	assert_str(_screen.handler.selected_bot_id).is_equal(actor.id)
	assert_bool(_screen.skill_buttons["strike"].disabled).is_false()


func test_cancel_button_drops_the_skill() -> void:
	_screen.skill_buttons["strike"].pressed.emit()
	assert_bool(_screen.cancel_button.disabled).is_false()
	assert_bool(_screen.handler.is_choosing_target()).is_true()
	_screen.cancel_button.pressed.emit()
	assert_bool(_screen.handler.is_choosing_target()).is_false()
	assert_bool(_screen.cancel_button.disabled).is_true()


func test_choosing_a_skill_highlights_the_targets() -> void:
	_screen.skill_buttons["strike"].pressed.emit()
	for c in _screen.fight.combatants:
		var expected := c.side == Combatant.Side.ENEMY and c.is_alive()
		var targetable: bool = _screen.unit_panels[c.id].highlight == _screen.UnitPanel.Highlight.TARGETABLE
		assert_bool(targetable).is_equal(expected)


func test_clicking_an_enemy_without_a_skill_shows_why() -> void:
	var enemy := _screen.fight.living(Combatant.Side.ENEMY)[0]
	Helpers.click(_screen.unit_panels[enemy.id])
	assert_str(_screen.message_label.text).is_equal("choose a skill first")
	assert_int(_screen.fight.action_count).is_equal(_screen.fight.action_tags.size())


func test_wait_button_waits() -> void:
	var actor := _screen.handler.actor()
	_screen.skill_buttons["strike"].pressed.emit()
	assert_str(_screen.wait_button.text).is_equal("WAIT for Strike")
	_screen.wait_button.pressed.emit()
	assert_bool(_screen.fight.action_tags.has("%s:wait" % actor.id)).is_true()


func test_enemy_intent_labels_and_preview_area_are_in_place() -> void:
	for c in _screen.fight.combatants:
		var panel = _screen.unit_panels[c.id]
		if c.side == Combatant.Side.ENEMY:
			assert_object(panel.intent_label).is_not_null()
			assert_str(panel.intent_label.name).is_equal("IntentLabel")
		else:
			assert_object(panel.intent_label).is_null()
	assert_object(_screen.preview_area).is_not_null()
	assert_bool(_screen.preview_area.is_inside_tree()).is_true()


func _upcoming_ids(length: int) -> Array[String]:
	var ids: Array[String] = []
	if _screen.fight.is_over():
		return ids
	for entry in _screen.fight.upcoming(length):
		ids.append(entry.combatant_id)
	return ids
