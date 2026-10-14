extends GdUnitTestSuite
## The battle layout (ui/README.md rules 10 and 16, the Slay the Spire / Into
## the Breach action design): one control strip, the log and preview drawer,
## the action dock with hotkeyed tiles, the focused card with every target's
## outcome, Esc to put a skill back, portrait turn order, and arrow badges
## that cover no card.

const Helpers := preload("res://tests/ui/fight/fight_ui_helpers.gd")

var _runner: GdUnitSceneRunner
var _screen: BattleScreen
var _speed := ""


func before_test() -> void:
	_speed = GameSettings.shared().animation_speed


func after_test() -> void:
	# The speed choice saves the setting; put the player's back as it was.
	GameSettings.shared().animation_speed = _speed
	GameSettings.shared().save()


func _start(screen: BattleScreen) -> void:
	_screen = screen
	_runner = scene_runner(auto_free(_screen))
	await _runner.simulate_frames(1)
	var guard := 0
	while _screen.handler.is_enemy_turn() and guard < 200:
		await _runner.simulate_frames(1)
		guard += 1


func _first_damage_skill() -> String:
	for skill in _screen.handler.actor().skills():
		if skill.is_damage() and _screen.handler.skill_problem(skill.id).is_empty():
			return skill.id
	return ""


func test_the_screen_has_one_control_strip() -> void:
	await _start(Helpers.screen())
	var strips: Array = _screen.find_children("*", "ControlStrip", true, false)
	assert_int(strips.size()).is_equal(1)
	for id in [&"speed", &"log", &"preview", &"view"]:
		assert_bool(id in _screen.control_strip.ids()).override_failure_message(str(id)).is_true()


func test_the_speed_choice_sets_the_animation_speed() -> void:
	await _start(Helpers.screen())
	_screen.control_strip.press(&"speed", &"2x")
	assert_str(GameSettings.shared().animation_speed).is_equal("2x")


func test_log_and_preview_open_in_a_drawer() -> void:
	await _start(Helpers.screen())
	assert_bool(_screen.drawer.visible).is_false()
	_screen.control_strip.press(&"log")
	assert_bool(_screen.drawer.visible).is_true()
	assert_bool(_screen.log_label.visible).is_true()
	assert_bool(_screen.preview_area.visible).is_false()
	_screen.control_strip.press(&"preview")
	assert_bool(_screen.preview_area.visible).is_true()
	_screen.control_strip.press(&"log")
	_screen.control_strip.press(&"preview")
	assert_bool(_screen.drawer.visible).is_false()


func test_compact_cards_show_flags_as_icons() -> void:
	await _start(Helpers.screen())
	_screen.control_strip.press(&"view", &"compact")
	await _runner.simulate_frames(1)
	for id: String in _screen.unit_panels:
		var panel = _screen.unit_panels[id]
		assert_bool(panel.compact).is_true()
		for f in panel.flags_row.get_children():
			if f is Flag and f.name != "Flag_outcome":
				assert_bool((f as Flag).label.visible).override_failure_message("%s %s" % [id, f.name]).is_false()


func test_the_dock_shows_the_acting_bot_and_hotkeyed_tiles() -> void:
	await _start(Helpers.screen())
	var actor := _screen.handler.actor()
	assert_str(_screen.dock_name.text).is_equal(actor.display_name)
	assert_bool(_screen.find_child("ActivePortrait", true, false).get_child(0) is UnitPortrait).is_true()
	var n := 0
	for id: String in _screen.skill_buttons:
		var tile: ActionTile = _screen.skill_buttons[id]
		if tile.visible:
			n += 1
			assert_int(tile.hotkey).is_equal(n)
	assert_int(n).is_equal(actor.skills().size())


func test_a_hotkey_picks_its_tile() -> void:
	await _start(Helpers.screen())
	var first := ""
	for id: String in _screen.skill_buttons:
		if _screen.skill_buttons[id].visible and not _screen.skill_buttons[id].disabled:
			first = id
			break
	assert_bool(_screen.press_hotkey(_screen.skill_buttons[first].hotkey)).is_true()
	assert_str(_screen.handler.selected_skill_id).is_equal(first)


func test_a_chosen_skill_lifts_into_the_focus_card_and_marks_every_target() -> void:
	await _start(Helpers.screen())
	var skill_id := _first_damage_skill()
	_screen.on_skill_pressed(skill_id)
	assert_bool(_screen.focus_card.visible).is_true()
	assert_str(_screen.focus_card.skill_id).is_equal(skill_id)
	assert_bool(_screen.prompt_label.visible).is_false()
	for c in _screen.fight.combatants:
		var panel = _screen.unit_panels[c.id]
		var target := c.is_alive() and _screen.handler.target_problem(c.id).is_empty()
		assert_bool(panel.find_child("Flag_outcome", true, false) != null).override_failure_message(c.id).is_equal(target)
		if target:
			var preview := _screen.telegraph.preview_choice(_screen.fight, FightAction.use(skill_id, c.id))
			var after := int(preview.effect_on(c.id).hp_after.value)
			assert_str(panel.target_outcome["text"]).is_equal(str(after - c.hp))


func test_a_lethal_target_is_marked_ko() -> void:
	await _start(Helpers.screen())
	var enemy := _screen.fight.living(Combatant.Side.ENEMY)[0]
	enemy.hp = 1
	_screen.on_skill_pressed(_first_damage_skill())
	assert_bool(_screen.unit_panels[enemy.id].target_outcome["ko"]).is_true()
	var flag: Flag = _screen.unit_panels[enemy.id].find_child("Flag_outcome", true, false)
	assert_str(flag.label.text).starts_with("KO")


func test_pointing_at_a_target_puts_its_math_on_the_card() -> void:
	await _start(Helpers.screen())
	_screen.on_skill_pressed(_first_damage_skill())
	var enemy := _screen.fight.living(Combatant.Side.ENEMY)[0]
	_screen.on_unit_hovered(enemy.id, true)
	assert_str(_screen.focus_card.math_label.get_parsed_text()).contains("DEF %d" % enemy.stats.defense)


func test_esc_puts_the_skill_back() -> void:
	await _start(Helpers.screen())
	_screen.on_skill_pressed(_first_damage_skill())
	assert_bool(_screen.handler.is_choosing_target()).is_true()
	var esc := InputEventAction.new()
	esc.action = &"ui_cancel"
	esc.pressed = true
	_screen._unhandled_input(esc)
	assert_bool(_screen.handler.is_choosing_target()).is_false()
	assert_bool(_screen.focus_card.visible).is_false()
	for id: String in _screen.unit_panels:
		assert_bool(_screen.unit_panels[id].target_outcome.is_empty()).is_true()


func test_the_turn_order_shows_portraits() -> void:
	await _start(Helpers.screen())
	var chips: Array = _screen.timeline_bar.get_children().filter(func(c: Node) -> bool: return c is PanelContainer)
	assert_bool(chips.is_empty()).is_false()
	for chip: Control in chips:
		assert_bool(chip.find_children("*", "UnitPortrait", true, false).is_empty()).is_false()


func test_badges_cover_no_unit_card() -> void:
	await _start(Helpers.screen())
	await _runner.simulate_frames(3)
	var cards: Array[Rect2] = []
	for id: String in _screen.unit_panels:
		var g: Rect2 = _screen.unit_panels[id].get_global_rect()
		cards.append(Rect2(_screen.arrows.get_global_transform().affine_inverse() * g.position, g.size))
	assert_bool(_screen.arrows.badge_rects.is_empty()).is_false()
	for b: Dictionary in _screen.arrows.badge_rects:
		for c in cards:
			assert_bool((b["rect"] as Rect2).intersects(c)).override_failure_message("badge over a card").is_false()


func test_hovering_a_unit_fades_the_other_arrows() -> void:
	await _start(Helpers.screen())
	var enemy := _screen.fight.living(Combatant.Side.ENEMY)[0]
	_screen.on_unit_hovered(enemy.id, true)
	assert_str(_screen.arrows.hover_id).is_equal(enemy.id)
	_screen.on_unit_hovered(enemy.id, false)
	assert_str(_screen.arrows.hover_id).is_equal("")
