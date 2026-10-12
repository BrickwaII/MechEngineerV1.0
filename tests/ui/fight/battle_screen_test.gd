extends GdUnitTestSuite
## The battle screen, headless. Clicks go through the panels' own input
## handlers and the buttons' pressed signals, as the mouse would.

const Helpers := preload("res://tests/ui/fight/fight_ui_helpers.gd")
const BATTLE_SCENE := preload("res://ui/fight/battle_screen.tscn")

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
		assert_int(int(panel.hp_bar.value)).is_equal(c.hp)
		assert_int(int(panel.hp_bar.max_value)).is_equal(c.max_hp)
		assert_int(int(panel.energy_bar.value)).is_equal(c.energy())
		assert_str(panel.hp_bar.text()).is_equal("HP %d/%d" % [c.hp, c.max_hp])


func test_panels_update_after_an_action() -> void:
	var target := _screen.fight.living(Combatant.Side.ENEMY)[0]
	var hp_before := target.hp
	_screen.skill_buttons["strike"].pressed.emit()
	Helpers.click(_screen.unit_panels[target.id])
	assert_int(target.hp).is_less(hp_before)
	assert_int(int(_screen.unit_panels[target.id].hp_bar.value)).is_equal(target.hp)


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
	assert_str(_screen.wait_button.label.text).is_equal("Wait for Strike")
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


## Plays bot turns by mouse until `bot_id` must act.
func _until_turn_of(bot_id: String) -> void:
	var guard := 0
	while _screen.handler.actor() != null and _screen.handler.actor().id != bot_id and guard < 50:
		if _screen.handler.is_player_turn():
			Helpers.play_turn_by_mouse(_screen)
		await _enemies_done()
		guard += 1


func test_a_support_bot_sees_only_its_own_skills_by_their_names() -> void:
	await _until_turn_of("stub_spark")
	var spark := _screen.handler.actor()
	assert_str(spark.id).is_equal("stub_spark")
	var shown: Array[String] = []
	for skill_id in _screen.skill_buttons:
		if _screen.skill_buttons[skill_id].visible:
			shown.append(skill_id)
	assert_array(shown).contains_exactly_in_any_order(spark.skill_ids)
	assert_str(_screen.skill_buttons["patch_up"].skill_name).is_equal("Patch Up")
	assert_str(_screen.skill_buttons["shield"].skill_name).is_equal("Shield Ally")
	# Overcharge Shot belongs to Bolt, not Spark.
	assert_bool(_screen.skill_buttons["heavy_strike"].visible).is_false()


func test_patch_up_heals_the_bot_clicked() -> void:
	await _until_turn_of("stub_spark")
	var hurt := _screen.fight.combatant("stub_bolt")
	hurt.hp = 10
	_screen.skill_buttons["patch_up"].pressed.emit()
	assert_str(_screen.prompt_label.text).contains("Click a bot")
	Helpers.click(_screen.unit_panels["stub_bolt"])
	assert_int(hurt.hp).is_greater(10)
	assert_str(_screen.fight.action_tags[-1]).is_equal("stub_spark:patch_up")


func test_shield_ally_marks_the_bots_panel() -> void:
	await _until_turn_of("stub_spark")
	_screen.skill_buttons["shield"].pressed.emit()
	_screen.on_unit_hovered("stub_anvil", true)
	assert_str(_screen.preview_label.text).contains("blocks 40% of its next hit")
	Helpers.click(_screen.unit_panels["stub_anvil"])
	assert_int(_screen.fight.combatant("stub_anvil").guard_percent).is_equal(40)
	assert_str(_screen.unit_panels["stub_anvil"].status_text()).contains("GUARD 40%")


func test_the_wait_ticks_box_is_hidden_by_default() -> void:
	assert_bool(_screen.wait_ticks_box.visible).is_false()
	assert_int(_screen.exact_wait_ticks()).is_equal(0)


func test_exact_waits_from_the_ticks_box() -> void:
	var v := FightVariants.defaults()
	v.choose(FightVariants.WAIT_LENGTH, FightVariants.WAIT_LENGTH_EXACT)
	var screen := BATTLE_SCENE.instantiate() as BattleScreen
	screen.setup(Helpers.request(), 1, Helpers.fast_tuning(), CombatTuning.load_default().with_variants(v))
	screen.enemy_turn_delay = 0.0
	var runner := scene_runner(auto_free(screen))
	await runner.simulate_frames(1)
	var guard := 0
	while screen.handler.is_enemy_turn() and guard < 200:
		await runner.simulate_frames(1)
		guard += 1
	assert_bool(screen.wait_ticks_box.visible).is_true()
	screen.wait_ticks_box.value = 3
	assert_str(screen.wait_button.label.text).is_equal("Wait 3 ticks")
	assert_bool(screen.wait_button.disabled).is_false()
	screen.wait_button.pressed.emit()
	assert_int(screen.fight.decision_tags.filter(func(t: ActionTag) -> bool: return t.kind == FightAction.Kind.WAIT).size()).is_equal(1)
	assert_str(screen.fight.log_text()).contains("waits 3 ticks")


func test_the_screen_follows_the_icon_style() -> void:
	# Skills are cards with cost and effect; stats are icons; the log starts collapsed.
	var strike: SkillCard = _screen.skill_buttons["strike"]
	assert_str(strike.cost_label.text).is_equal(str(_screen.fight.tuning.skill("strike").energy_cost))
	assert_str(strike.effect).starts_with("Deal ")
	assert_bool(_screen.log_label.visible).is_false()
	_screen.toggle_log()
	assert_bool(_screen.log_label.visible).is_true()
	assert_str(_screen.defense_stat.value_text()).is_equal(str(_screen.fight.request.defense_level))
	for id: String in _screen.unit_panels:
		var panel = _screen.unit_panels[id]
		assert_object(panel.stat_icons["atk"]).is_not_null()
		assert_str(UiTooltip.spec(panel.stat_icons["atk"])["title"]).is_equal("Attack")
		if panel.is_enemy and panel.intent_kind != "":
			assert_bool(panel.intent_chip.visible).override_failure_message(id).is_true()


func test_skill_card_face_splits_rank_and_writes_the_effect() -> void:
	var s := CombatSkill.new("strike", "Mega Strike +2", 0, 150, CombatSkill.EFFECT_DAMAGE)
	s.names_rank = true
	s.pierce_percent = 20
	var face := BattleScreen.skill_card_face(s, 10)
	assert_str(face.name).is_equal("Mega Strike")
	assert_str(face.rank).is_equal("+2")
	assert_str(face.effect).is_equal("Deal 15. Pierce 20%.")
	var guard := CombatSkill.new("brace", "Brace", 2, 40, CombatSkill.EFFECT_GUARD, CombatSkill.TARGET_SELF)
	assert_str(BattleScreen.skill_card_face(guard, 10).effect).is_equal("Guard 40% self.")
	var all := CombatSkill.new("arc", "Arc Sweep", 6, 70, CombatSkill.EFFECT_DAMAGE, CombatSkill.TARGET_ALL_OPPONENTS)
	all.level = 2
	var f := BattleScreen.skill_card_face(all, 10)
	assert_str(f.effect).is_equal("Deal 7 to all.")
	assert_str(f.rank).is_equal("Lv2")
