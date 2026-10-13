extends GdUnitTestSuite
## Battle unit cards on the card anatomy (ui/README.md rule 8): the sprite
## alone, three headlines (HP with Energy, ATK, next turn), flags on the edge,
## ⋮ / right-click detail, and math tooltips on damage badges and turn order.

const Helpers := preload("res://tests/ui/fight/fight_ui_helpers.gd")

var _runner: GdUnitSceneRunner
var _screen: BattleScreen


func after_test() -> void:
	DetailModal.close_current()
	UiTooltip.hide_tooltip()


func _start(screen: BattleScreen) -> void:
	_screen = screen
	_runner = scene_runner(auto_free(_screen))
	await _runner.simulate_frames(1)
	var guard := 0
	while _screen.handler.is_enemy_turn() and guard < 200:
		await _runner.simulate_frames(1)
		guard += 1


func _enemy_panel():
	for id: String in _screen.unit_panels:
		if _screen.unit_panels[id].is_enemy and _screen.fight.combatant(id).is_alive():
			return _screen.unit_panels[id]
	return null


func test_a_card_has_three_headlines_hp_atk_and_next_turn() -> void:
	await _start(Helpers.screen())
	for id: String in _screen.unit_panels:
		var panel = _screen.unit_panels[id]
		var c := _screen.fight.combatant(id)
		assert_array(panel.strip.kinds()).is_equal(["bar", "number", "chip"])
		assert_object(panel.strip.headline(0).meter).is_same(panel.hp_bar)
		assert_bool(panel.energy_bar.get_parent().get_parent() == panel.strip.headline(0)).is_true()
		assert_str(panel.strip.headline(0).value_label.text).is_equal("%d/%d" % [c.hp, c.max_hp])
		assert_str(panel.strip.headline(1).value_label.text).is_equal(str(c.stats.attack))
		assert_str(UiTooltip.spec(panel.strip.headline(0))["numbers"]).contains("Energy %d/" % c.energy())


func test_nothing_is_drawn_over_the_sprite() -> void:
	await _start(Helpers.screen())
	for id: String in _screen.unit_panels:
		var panel = _screen.unit_panels[id]
		for part: Control in [panel.strip, panel.flags_row, panel.name_label, panel.more_button]:
			assert_bool(panel.view.is_ancestor_of(part)).override_failure_message(id).is_false()
			assert_bool(panel.view.get_global_rect().intersects(part.get_global_rect())) \
				.override_failure_message("%s overlaps the sprite on %s" % [part.name, id]).is_false()


func test_the_unit_acting_now_shows_now_and_the_others_their_place() -> void:
	await _start(Helpers.screen())
	var upcoming := _screen.fight.upcoming(_screen.tuning.timeline_length)
	var actor := _screen.handler.actor()
	assert_str(_screen.unit_panels[actor.id].strip.headline(2).value_label.text).is_equal("Now")
	for id: String in _screen.unit_panels:
		var info: Dictionary = _screen.unit_panels[id].turn_info
		var pos: int = info["position"]
		if pos > 0:
			assert_str(info["chip"]).is_equal(BattleMath.ordinal(pos + 1))
			assert_str(upcoming[pos].combatant_id).is_equal(id)
		assert_array(info["math"]).is_not_empty()


func test_ordinals() -> void:
	assert_array([1, 2, 3, 4, 11, 12, 13, 21, 22].map(BattleMath.ordinal)).is_equal(
		["1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "22nd"])


func test_a_low_unit_and_the_boss_get_their_flags() -> void:
	await _start(Helpers.screen())
	var panel = _enemy_panel()
	var c := _screen.fight.combatant(panel.unit_id)
	_screen.show_boss(c.id, c.display_name)
	_screen.refresh()
	assert_object(panel.find_child("Flag_boss", true, false)).is_not_null()
	assert_object(panel.find_child("Flag_elite", true, false)).is_null()
	c.hp = 1
	_screen.refresh()
	await _runner.simulate_frames(1)
	assert_object(panel.find_child("Flag_low_hp", true, false)).is_not_null()


func test_a_status_shows_as_a_flag_with_its_number() -> void:
	await _start(Helpers.screen())
	var c := _screen.fight.living(Combatant.Side.PLAYER)[0]
	c.guard_percent = 40
	_screen.refresh()
	var flag: Flag = _screen.unit_panels[c.id].status_row.find_child("Status_guard", true, false)
	assert_object(flag).is_not_null()
	assert_str(flag.label.text).is_equal("Guard 40%")
	assert_str(_screen.unit_panels[c.id].stats_text()).contains("DEF %d+40%%" % c.stats.defense)


func test_the_more_button_opens_every_stat_skill_and_status() -> void:
	await _start(Helpers.screen())
	var panel = _enemy_panel()
	panel.more_button.pressed.emit()
	var m := DetailModal.current
	assert_object(m).is_not_null()
	assert_str(m.title).is_equal(_screen.fight.combatant(panel.unit_id).display_name)
	var ids := m.tabs.ids()
	assert_array(ids).contains([&"stats", &"skills", &"status"])
	if not panel.intent_text.is_empty():
		assert_array(ids).contains([&"next"])
	var rows: GridContainer = m.tabs.page(&"stats")
	var names: Array = []
	for i in range(1, rows.get_child_count(), 3):
		names.append((rows.get_child(i) as Label).text)
	assert_array(names).is_equal(["HP", "Energy", "Attack", "Defense", "Speed", "Battery", "Elasticity"])
	var skills: Control = m.tabs.page(&"skills")
	assert_int(skills.get_child_count()).is_equal(_screen.fight.combatant(panel.unit_id).skills().size())


func test_right_click_opens_the_detail_unless_a_skill_is_being_aimed() -> void:
	await _start(Helpers.screen())
	var panel = _enemy_panel()
	Helpers.click(panel, MOUSE_BUTTON_RIGHT)
	assert_bool(DetailModal.is_open()).is_true()
	DetailModal.close_current()
	_screen.skill_buttons["strike"].pressed.emit()
	assert_bool(_screen.handler.is_choosing_target()).is_true()
	Helpers.click(panel, MOUSE_BUTTON_RIGHT)
	assert_bool(DetailModal.is_open()).is_false()
	assert_bool(_screen.handler.is_choosing_target()).is_false()


func test_a_bot_detail_has_its_personality_hexagon() -> void:
	await _start(Helpers.screen())
	var bot = _screen.unit_panels[_screen.fight.living(Combatant.Side.PLAYER)[0].id]
	var ends: Array[float] = [0.6, 0.1, 0.0, 0.3, 0.0, 0.2]
	bot.personality_ends = ends
	var spec: Dictionary = bot.detail_spec()
	var personality: Array = (spec["sections"] as Array).filter(func(s: Dictionary) -> bool: return s["id"] == "personality")
	assert_int(personality.size()).is_equal(1)
	assert_object(personality[0]["content"].find_child("Hexagon", true, false)).is_not_null()
	for s: Dictionary in spec["sections"]:
		(s["content"] as Node).free()
	for f: Node in spec["flags"]:
		f.free()


func test_damage_math_uses_the_real_values_and_matches_the_rules() -> void:
	await _start(Helpers.screen())
	var f := _screen.fight
	var a := f.living(Combatant.Side.ENEMY)[0]
	var t := f.living(Combatant.Side.PLAYER)[0]
	var skill: CombatSkill = null
	for sk in a.skills():
		if sk.is_damage():
			skill = sk
			break
	var base := DamageRules.damage(a.stats, t.stats, skill, f.tuning)
	var lines := BattleMath.damage_lines(f, a.id, t.id, skill.id, base)
	var text: String = (lines[0] as UiFormula).text()
	assert_str(text).starts_with("ATK %d × Power %d%%" % [a.stats.attack, skill.power_percent])
	assert_str(text).contains("DEF %d" % t.stats.defense)
	assert_str(text).ends_with("= %d" % base)


func test_a_guard_adds_its_line_to_the_damage_math() -> void:
	await _start(Helpers.screen())
	var f := _screen.fight
	var a := f.living(Combatant.Side.ENEMY)[0]
	var t := f.living(Combatant.Side.PLAYER)[0]
	t.guard_percent = 50
	var skill := a.skills()[0]
	var amount := DamageRules.damage_to(a, t, skill, f.tuning)
	var lines := BattleMath.damage_lines(f, a.id, t.id, skill.id, amount)
	var guard_line: Variant = lines.filter(func(l: Variant) -> bool: return l is UiFormula and (l as UiFormula).text().contains("Guard 50%"))
	assert_int((guard_line as Array).size()).is_equal(1)
	assert_str((guard_line[0] as UiFormula).text()).ends_with("= %d" % amount)


func test_every_enemy_badge_gets_a_hotspot_with_its_math() -> void:
	await _start(Helpers.screen())
	await _runner.simulate_frames(3)
	var found := 0
	for a: Dictionary in _screen.arrows.arrows:
		if a.player or a.ghost or a.badge == null:
			continue
		var h: Control = _screen.arrows.hotspot_for(a.from, a.to)
		assert_object(h).is_not_null()
		var spec := UiTooltip.spec(h)
		assert_str(spec["title"]).contains((a.badge as ArrowBadge).text())
		assert_array(spec["math"]).is_not_empty()
		found += 1
	assert_int(found).is_greater(0)


func test_timeline_chips_explain_when_the_unit_acts() -> void:
	await _start(Helpers.screen())
	var chips: Array = _screen.timeline_bar.get_children().filter(func(c: Node) -> bool: return c is PanelContainer)
	assert_bool(chips.is_empty()).is_false()
	var with_math := chips.filter(func(c: Control) -> bool: return not (UiTooltip.spec(c).get("math", []) as Array).is_empty())
	assert_bool(with_math.is_empty()).is_false()


func test_a_lone_enemy_of_its_kind_has_no_number() -> void:
	var base := EnemyTable.load_default()
	var ids: Array[String] = []
	ids.assign([base.enemies.keys()[0], base.enemies.keys()[1], base.enemies.keys()[1]])
	var table := FixedEnemyTable.from_table(base, ids)
	var screen: BattleScreen = load("res://ui/fight/battle_screen.tscn").instantiate()
	screen.setup(Helpers.request(5), 7, Helpers.fast_tuning(), null, table)
	await _start(screen)
	var names: Array = _screen.fight.combatants.filter(func(c: Combatant) -> bool: return c.side == Combatant.Side.ENEMY) \
		.map(func(c: Combatant) -> String: return c.display_name)
	assert_array(names).is_equal([base.name_of(ids[0]), "%s 1" % base.name_of(ids[1]), "%s 2" % base.name_of(ids[1])])
