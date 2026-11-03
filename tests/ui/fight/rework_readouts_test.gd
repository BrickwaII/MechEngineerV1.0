extends GdUnitTestSuite
## The combat rework on the battle screen (S7): Exposed, Brace, plating pips,
## Stagger and wind-ups on the cards, their ends marked on the timeline,
## intent changes that animate, and the new actions' card text.

const A := preload("res://tests/fight/archetypes/archetype_test_helpers.gd")
const Helpers := preload("res://tests/ui/fight/fight_ui_helpers.gd")
const BATTLE_SCENE := preload("res://ui/fight/battle_screen.tscn")

var _runner: GdUnitSceneRunner
var _screen: BattleScreen


## A battle screen on `fight`'s request, tuning and enemies, played to the
## squad's first turn.
func _open(fight: Fight) -> BattleScreen:
	_screen = BATTLE_SCENE.instantiate()
	_screen.setup(fight.request, fight.fight_seed, Helpers.fast_tuning(), fight.tuning, fight.enemy_table)
	_runner = scene_runner(auto_free(_screen))
	await _runner.simulate_frames(1)
	await _enemies_done()
	return _screen


func _enemies_done() -> void:
	var guard := 0
	while _screen.handler.is_enemy_turn() and guard < 200:
		await _runner.simulate_frames(1)
		guard += 1


func _enemy(id_prefix: String) -> Combatant:
	for c in _screen.fight.combatants:
		if c.id.begins_with(id_prefix):
			return c
	return null


func test_plating_shows_as_pips() -> void:
	await _open(A.plated_fight())
	var plated := _enemy("plated")
	var panel = _screen.unit_panels[plated.id]
	assert_str(panel.status_row.shown.get("plating", "")).is_equal("PLATING 4/4")
	plated.plating = 1
	_screen.refresh()
	assert_str(panel.status_row.shown.get("plating", "")).is_equal("PLATING 1/4")
	var flag: Flag = panel.flags_row.get_node("Status_plating")
	var pips = flag.get_node("Row/Pips")
	assert_int(pips.whole).is_equal(1)
	assert_int(pips.most).is_equal(4)


func test_exposed_shows_its_bonus_and_is_marked_where_it_ends() -> void:
	await _open(A.plated_fight())
	var plated := _enemy("plated")
	_screen.fight.statuses.apply(plated, "exposed", _screen.handler.actor().id, 0)
	_screen.refresh()
	var bonus: int = _screen.fight.tuning.statuses.get_status("exposed").amount
	assert_str(_screen.unit_panels[plated.id].status_row.shown.get("exposed", "")).is_equal("EXPOSED +%d%%" % bonus)
	var slot := _screen.timeline_bar.shown_ids.find(plated.id)
	assert_int(slot).is_greater(0)
	assert_array(_screen.timeline_bar.marks_on(slot)).contains(["status_exposed"])
	# Only its next slot: that is when it wears off.
	var later := _screen.timeline_bar.shown_ids.find(plated.id, slot + 1)
	if later > 0:
		assert_array(_screen.timeline_bar.marks_on(later)).is_empty()


func test_brace_has_its_own_flag_and_ends_on_the_holders_next_slot() -> void:
	await _open(A.plated_fight())
	var bot := _screen.handler.actor()
	_screen.send(FightCommand.select_skill("brace"))
	_screen.send(FightCommand.select_target(bot.id))
	await _enemies_done()
	if bot.brace_absorb <= 0:
		return # the Plated hit used the Brace up before the screen came back
	var panel = _screen.unit_panels[bot.id]
	assert_str(panel.status_row.shown.get("brace", "")).is_equal("BRACE %d" % bot.brace_absorb)
	assert_bool(panel.status_row.shown.has("guard")).is_false()
	var slot := _screen.timeline_bar.shown_ids.find(bot.id)
	assert_array(_screen.timeline_bar.marks_on(slot)).contains(["status_brace"])


func test_a_staggered_enemy_shows_it_and_its_lost_turn() -> void:
	await _open(A.plated_fight())
	var plated := _enemy("plated")
	plated.plating = 0
	plated.staggered = true
	_screen.refresh()
	var bonus := _screen.fight.tuning.stagger.damage_bonus_percent
	assert_str(_screen.unit_panels[plated.id].status_row.shown.get("staggered", "")).is_equal("STAGGERED +%d%%" % bonus)
	var slot := _screen.timeline_bar.shown_ids.find(plated.id)
	assert_array(_screen.timeline_bar.marks_on(slot)).contains(["status_staggered"])


func test_a_wind_up_shows_its_hit_on_the_card_and_where_it_lands() -> void:
	await _open(A.charger_fight())
	var charger := _enemy("charger")
	# Play until the Charger has committed its Ram (strike, wind-up, Ram).
	var guard := 0
	while charger.committed == null and not _screen.fight.is_over() and guard < 30:
		Helpers.play_turn_by_mouse(_screen)
		await _enemies_done()
		guard += 1
	assert_object(charger.committed).is_not_null()
	var panel = _screen.unit_panels[charger.id]
	assert_str(panel.status_row.shown.get("wind_up", "")).is_equal("WIND-UP %s" % charger.skill("ram").display_name)
	assert_bool(panel.status_row.shown.has("charging")).is_false()
	assert_str(panel.intent_kind).is_equal("wind_up")
	assert_str(panel.intent_chip.icon_id).is_equal("intent_wind_up")
	var slot := _screen.timeline_bar.shown_ids.find(charger.id)
	assert_array(_screen.timeline_bar.marks_on(slot)).contains(["intent_wind_up"])


func test_an_intent_that_changes_animates() -> void:
	await _open(A.charger_fight())
	var charger := _enemy("charger")
	var panel = _screen.unit_panels[charger.id]
	var flips: int = panel.intent_flips
	var guard := 0
	# The Charger's pattern changes its intent every turn.
	while panel.intent_flips == flips and not _screen.fight.is_over() and guard < 10:
		Helpers.play_turn_by_mouse(_screen)
		await _enemies_done()
		guard += 1
	assert_int(panel.intent_flips).is_greater(flips)


func test_new_actions_say_what_they_do() -> void:
	var t := CombatTuning.load_default()
	assert_str(BattleScreen.skill_card_face(t.skill("shred"), 10).effect).is_equal("Deal 5 ×2. Apply Exposed.")
	var heavy := t.skill("heavy_strike")
	assert_str(BattleScreen.skill_card_face(heavy, 10).effect).is_equal(
		"Deal 15. +%d%% vs Exposed. Recovery %d%%." % [heavy.payoff_bonus_percent, heavy.recovery])
	assert_str(BattleScreen.skill_card_face(t.skill("strike"), 10).effect).is_equal("Deal 10.")


func test_the_new_keywords_have_glossary_entries_and_icons() -> void:
	for k in ["Exposed", "Brace", "Plating", "Stagger", "Recovery", "Wind-up", "Combo"]:
		assert_str(UiGlossary.keyword(k)).is_equal(k)
	assert_str(UiGlossary.keyword("Staggered")).is_equal("Stagger")
	for id in ["status_exposed", "status_brace", "status_plating", "status_staggered", "intent_wind_up"]:
		assert_bool(UiIcons.has(id)).is_true()
		assert_object(UiIcons.texture(id)).is_not_null()
	assert_array(UiGlossary.find_keywords("Deal 5 ×2. Apply Exposed.")).contains(["Exposed"])


func test_timeline_marks_read_a_copy_without_changing_it() -> void:
	var fight := A.plated_fight()
	var actor := fight.advance()
	var plated := fight.combatant("plated#1")
	if plated == null:
		plated = fight.living(Combatant.Side.ENEMY)[0]
	fight.statuses.apply(plated, "exposed", actor.id, 0)
	actor.brace_absorb = 5
	var upcoming := fight.upcoming(8)
	var marks := TimelineMarks.of(fight, upcoming)
	var plated_slot := -1
	var actor_slot := -1
	for i in upcoming.size():
		if plated_slot < 0 and upcoming[i].combatant_id == plated.id:
			plated_slot = i
		if actor_slot < 0 and upcoming[i].combatant_id == actor.id:
			actor_slot = i
	assert_str(marks[plated_slot][0].icon).is_equal("status_exposed")
	assert_str(marks[actor_slot][0].icon).is_equal("status_brace")
	# Nothing changed.
	assert_bool(plated.has_status("exposed")).is_true()
	assert_int(actor.brace_absorb).is_equal(5)
