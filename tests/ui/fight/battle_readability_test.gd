extends GdUnitTestSuite
## Battle readability (R1-B), headless: damage badges on the arrows, the
## player's own arrow, KO marks, hp and energy slices, stat chips, the detail
## card, and the NEXT bar's hover and order preview.

const Helpers := preload("res://tests/ui/fight/fight_ui_helpers.gd")
const StatusRowScript := preload("res://ui/fight/status_row.gd")

var _runner: GdUnitSceneRunner
var _screen: BattleScreen


func _start(screen: BattleScreen) -> void:
	_screen = screen
	_runner = scene_runner(auto_free(_screen))
	await _runner.simulate_frames(1)
	var guard := 0
	while _screen.handler.is_enemy_turn() and guard < 200:
		await _runner.simulate_frames(1)
		guard += 1


func _hover(unit_id: String, inside := true) -> void:
	_screen.unit_panels[unit_id].hovered.emit(unit_id, inside)


func _player_arrows() -> Array:
	return _screen.arrows.arrows.filter(func(a: Dictionary) -> bool: return a.player)


func test_every_enemy_arrow_carries_its_intent_badge() -> void:
	await _start(Helpers.screen())
	var enemy_arrows := _screen.arrows.arrows.filter(func(a: Dictionary) -> bool: return not a.player and not a.ghost)
	assert_int(enemy_arrows.size()).is_greater_equal(_screen.telegraph.tracker.current.size())
	for a: Dictionary in enemy_arrows:
		var intent := _screen.telegraph.intent_of(a.from)
		var badge: ArrowBadge = a.badge
		assert_object(badge).is_not_null()
		if not _screen.fight.combatant(a.from).skill(intent.skill_id()).hits_all():
			assert_int(badge.amount.value).is_equal(mini(intent.amount, _screen.fight.combatant(a.to).hp))
	assert_int(_screen.arrows.badge_texts().size()).is_equal(enemy_arrows.size())


func test_hovering_a_target_draws_the_bots_own_arrow_with_its_damage() -> void:
	await _start(Helpers.healer_screen())
	_screen.skill_buttons["heavy_strike"].pressed.emit()
	assert_array(_player_arrows()).is_empty()
	_hover("warden_mech#1")
	var mine := _player_arrows()
	assert_int(mine.size()).is_equal(1)
	var effect := _screen.shown_preview.effect_on("warden_mech#1")
	assert_str(mine[0].badge.text()).is_equal(effect.damage.text())
	assert_bool(mine[0].badge.knocks_out).is_false()
	_hover("warden_mech#1", false)
	assert_array(_player_arrows()).is_empty()


func test_a_hit_that_would_down_the_target_shows_a_ko_mark() -> void:
	await _start(Helpers.healer_screen())
	_screen.fight.combatant("warden_mech#1").hp = 3
	_screen.skill_buttons["strike"].pressed.emit()
	_hover("warden_mech#1")
	assert_bool(_player_arrows()[0].badge.knocks_out).is_true()
	assert_str(_player_arrows()[0].badge.text()).is_equal("3")
	assert_array(_screen.arrows.badge_texts()).contains(["bolt>warden_mech#1 3 KO"])
	# The downed enemy's own arrow is a ghost: it would never act.
	var ghosts := _screen.arrows.arrows.filter(func(a: Dictionary) -> bool: return a.ghost and a.from == "warden_mech#1")
	assert_int(ghosts.size()).is_equal(1)


func test_arrows_the_choice_would_change_show_the_new_value() -> void:
	await _start(Helpers.healer_screen())
	_screen.skill_buttons["heavy_strike"].pressed.emit()
	_hover("warden_mech#1")
	# The second Warden would switch from hitting Bolt to repairing the first.
	var medic := _screen.arrows.arrows.filter(func(a: Dictionary) -> bool: return a.from == "warden_mech#2" and not a.ghost)
	assert_int(medic.size()).is_equal(1)
	assert_str(medic[0].kind).is_equal(ArrowBadge.HEAL)
	assert_bool(medic[0].changed).is_true()
	var change := _screen.shown_preview.change_for("warden_mech#2")
	assert_str(medic[0].badge.text()).is_equal("+%d" % change.new_intent.amount)
	var old := _screen.arrows.arrows.filter(func(a: Dictionary) -> bool: return a.from == "warden_mech#2" and a.ghost)
	assert_int(old.size()).is_equal(1)
	assert_str(old[0].to).is_equal("bolt")


func test_the_hp_bar_shows_the_slice_the_hit_would_take() -> void:
	await _start(Helpers.healer_screen())
	_screen.skill_buttons["heavy_strike"].pressed.emit()
	_hover("warden_mech#1")
	var bar = _screen.unit_panels["warden_mech#1"].hp_bar
	assert_bool(bar.has_preview()).is_true()
	assert_int(int(bar.preview_to)).is_equal(_screen.shown_preview.effect_on("warden_mech#1").hp_after.value)
	assert_float(bar.preview_to).is_less(bar.value)


func test_a_heal_shows_a_green_slice_past_the_fill() -> void:
	await _start(Helpers.screen())
	var actor := _screen.handler.actor()
	# Find a bot with a heal and a hurt friend; Spark starts at 22 of 25.
	var healer: Combatant = null
	for c in _screen.fight.living(Combatant.Side.PLAYER):
		if c.has_skill("patch_up"):
			healer = c
	if healer == null or healer != actor:
		return
	_screen.skill_buttons["patch_up"].pressed.emit()
	_hover(healer.id)
	var bar = _screen.unit_panels[healer.id].hp_bar
	assert_float(bar.preview_to).is_greater(bar.value)


func test_the_energy_bar_shows_the_selected_skills_cost() -> void:
	await _start(Helpers.healer_screen())
	var bolt := _screen.fight.combatant("bolt")
	var bar = _screen.unit_panels["bolt"].energy_bar
	assert_bool(bar.has_preview()).is_false()
	_screen.skill_buttons["heavy_strike"].pressed.emit()
	assert_bool(bar.has_preview()).is_true()
	assert_int(int(bar.preview_to)).is_equal(BattleReadout.energy_after(bolt, bolt.skill("heavy_strike")))
	_screen.cancel_button.pressed.emit()
	assert_bool(bar.has_preview()).is_false()


func test_every_panel_shows_its_stats_and_a_full_detail_card() -> void:
	await _start(Helpers.screen())
	for c in _screen.fight.combatants:
		var panel = _screen.unit_panels[c.id]
		var s := c.stats
		if c.guard_percent == 0:
			assert_str(panel.stats_text()).is_equal("ATK %d DEF %d SPD %d BAT %d" % [s.attack, s.defense, s.speed, s.battery_capacity])
		var detail: String = panel.detail_text()
		assert_str(detail).contains("ATK %d" % s.attack)
		assert_str(detail).contains("ELA %d" % s.elasticity)
		for skill in c.skills():
			assert_str(detail).contains("%s Lv%d  %d EN" % [skill.display_name, skill.level, skill.energy_cost])
		assert_str(detail).contains("STATUS")
		var card: Control = panel._make_custom_tooltip("")
		assert_object(card).is_not_null()
		card.free()


func test_a_guard_shows_on_the_defense_chip() -> void:
	await _start(Helpers.screen())
	var c := _screen.fight.living(Combatant.Side.PLAYER)[0]
	c.guard_percent = 40
	_screen.refresh()
	assert_str(_screen.unit_panels[c.id].stats_text()).contains("DEF %d+40%%" % c.stats.defense)


func test_hovering_a_unit_lights_its_slots_on_the_next_bar() -> void:
	await _start(Helpers.screen())
	var bar := _screen.timeline_bar
	var enemy := _screen.fight.living(Combatant.Side.ENEMY)[0]
	_hover(enemy.id)
	var expected: Array[int] = []
	for i in bar.shown_ids.size():
		if bar.shown_ids[i] == enemy.id:
			expected.append(i)
	assert_array(bar.lit_slots()).is_equal(expected)
	_hover(enemy.id, false)
	assert_array(bar.lit_slots()).is_empty()


func test_a_choice_that_changes_the_order_previews_the_shift() -> void:
	await _start(Helpers.screen())
	var bar := _screen.timeline_bar
	# An empty battery, so the bot has a skill to wait for.
	_screen.handler.actor().energy_milli = 0
	_screen.refresh()
	var current := _screen.fight.upcoming(_screen.tuning.timeline_length)
	assert_bool(bar.showing_preview).is_false()
	# Pointing at WAIT previews the wait; a wait holds the bot back.
	_screen.on_wait_hovered(true)
	var choice := _screen.shown_preview
	assert_object(choice).is_not_null()
	var order := BattleReadout.order_with_choice(current, choice)
	var shifts := not BattleReadout.same_order(order, current)
	assert_bool(bar.showing_preview).is_equal(shifts)
	var ids: Array[String] = []
	for e in (order if shifts else current):
		ids.append(e.combatant_id)
	assert_array(bar.shown_ids).is_equal(ids)
	_screen.on_wait_hovered(false)
	assert_bool(bar.showing_preview).is_false()


func test_no_preview_text_sits_under_the_sprites() -> void:
	await _start(Helpers.healer_screen())
	_screen.skill_buttons["heavy_strike"].pressed.emit()
	_hover("warden_mech#1")
	for id: String in _screen.unit_panels:
		var panel = _screen.unit_panels[id]
		assert_bool(panel.preview_label.visible).is_false()
		if panel.is_enemy:
			assert_bool(panel.intent_row.visible).is_false()
	# The log stays, collapsed until opened (ui/README.md rule 5).
	assert_bool(_screen.log_label.visible).is_false()
	assert_bool(_screen.log_toggle.visible).is_true()


func test_status_icons_show_only_their_number_and_tooltip_the_word() -> void:
	assert_str(StatusRowScript.number_of("GUARD 40%")).is_equal("40%")
	assert_str(StatusRowScript.number_of("CHARGE >6")).is_equal(">6")
	assert_str(StatusRowScript.number_of("LOW EN")).is_empty()
	var row = auto_free(StatusRowScript.new())
	row.show_statuses({"guard": "GUARD 40%", "low_energy": "LOW EN"})
	var guard: Control = row.get_node("Status_guard")
	assert_str(UiTooltip.spec(guard)["numbers"]).is_equal("GUARD 40%")
	assert_str(row.text()).is_equal("GUARD 40% · LOW EN")
