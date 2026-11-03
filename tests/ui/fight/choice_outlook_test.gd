extends GdUnitTestSuite
## The focused card's outlook (S7): where a choice lands the bot on the
## timeline, conditional combos, a peek at a tile before it is picked, and
## Wait's card (free, what it banks).

const A := preload("res://tests/fight/archetypes/archetype_test_helpers.gd")
const T := preload("res://tests/fight/intent/intent_test_helpers.gd")
const Helpers := preload("res://tests/ui/fight/fight_ui_helpers.gd")
const BATTLE_SCENE := preload("res://ui/fight/battle_screen.tscn")

var _runner: GdUnitSceneRunner
var _screen: BattleScreen


func _open(fight: Fight) -> BattleScreen:
	_screen = BATTLE_SCENE.instantiate()
	_screen.setup(fight.request, fight.fight_seed, Helpers.fast_tuning(), fight.tuning, fight.enemy_table)
	_runner = scene_runner(auto_free(_screen))
	await _runner.simulate_frames(1)
	var guard := 0
	while _screen.handler.is_enemy_turn() and guard < 200:
		await _runner.simulate_frames(1)
		guard += 1
	return _screen


func _enemy(prefix: String) -> Combatant:
	for c in _screen.fight.living(Combatant.Side.ENEMY):
		if c.id.begins_with(prefix):
			return c
	return null


func test_aiming_shows_where_the_bot_lands() -> void:
	await _open(A.plated_fight())
	var target := _enemy("plated")
	_screen.on_skill_pressed("heavy_strike")
	_screen.preview_target(target.id)
	var land := _screen.landing
	assert_int(int(land.slot)).is_greater_equal(0)
	var text := _screen.outlook.landing_label.get_parsed_text()
	assert_str(text).contains("Next turn: %s" % ChoiceReadout.landing_text(land))
	# The AFTER bar lights the same slot, with the bot in it.
	var bar := _screen.timeline_bar
	assert_bool(bar.showing_preview).is_true()
	assert_str(bar.shown_ids[bar.landing_slot]).is_equal(_screen.handler.actor().id)
	assert_str(BattleMath.ordinal(bar.landing_slot + 1)).is_equal(ChoiceReadout.landing_text(land).split(",")[0])
	# Heavy Strike's recovery is named.
	assert_str(text).contains("Recovery %d%%" % _screen.fight.tuning.skill("heavy_strike").recovery)


func test_pointing_at_a_tile_peeks_at_its_card() -> void:
	await _open(A.plated_fight())
	_screen.on_tile_hovered("shred", true)
	assert_bool(_screen.focus_card.visible).is_true()
	assert_str(_screen.focus_card.skill_id).is_equal("shred")
	assert_str(_screen.focus_card.cost_label.text).is_equal("2")
	assert_bool(_screen.outlook.landing_label.visible).is_true()
	assert_bool(_screen.handler.is_choosing_target()).is_false()
	assert_bool(_screen.timeline_bar.showing_preview).is_true()
	_screen.on_tile_hovered("shred", false)
	assert_bool(_screen.focus_card.visible).is_false()
	assert_bool(_screen.timeline_bar.showing_preview).is_false()


func test_wait_reads_as_free_and_says_what_it_banks() -> void:
	await _open(A.plated_fight())
	var actor := _screen.handler.actor()
	actor.energy_milli = 0
	_screen.refresh()
	assert_str(_screen.wait_free.value_label.text).starts_with("Free +")
	assert_str(UiTooltip.spec(_screen.wait_button)["body"]).contains("Free")
	assert_str(UiTooltip.spec(_screen.wait_button)["numbers"]).contains("Banks +")
	_screen.on_wait_hovered(true)
	assert_bool(_screen.focus_card.visible).is_true()
	assert_str(_screen.focus_card.cost_label.text).is_equal("Free")
	var land := _screen.landing
	var gain := int(land.energy_at_turn) - actor.energy()
	assert_int(gain).is_greater(0)
	assert_str(_screen.focus_card.math_label.get_parsed_text()).contains(str(int(land.energy_at_turn)))
	assert_str(_screen.outlook.landing_label.get_parsed_text()).contains("Next turn")
	_screen.on_wait_hovered(false)
	assert_bool(_screen.focus_card.visible).is_false()


func test_a_payoff_says_what_it_would_deal_after_the_setup() -> void:
	await _open(A.plated_fight())
	var target := _enemy("plated")
	_screen.on_skill_pressed("heavy_strike")
	_screen.preview_target(target.id)
	var combo := _screen.outlook.combo_label.get_parsed_text()
	var p := ChoiceReadout.payoff_combo(_screen.fight, _screen.handler.actor(), _screen.handler.actor().skill("heavy_strike"), target)
	assert_int(int(p.combo)).is_greater(int(p.now))
	# The other bot holds Shred.
	assert_str(combo).contains("%d now. %d if " % [p.now, p.combo])
	assert_str(combo).contains("puts Exposed on first")


func test_a_setup_names_the_hit_that_cashes_it_in() -> void:
	await _open(A.plated_fight())
	var target := _enemy("plated")
	_screen.on_skill_pressed("shred")
	_screen.preview_target(target.id)
	var combo := _screen.outlook.combo_label.get_parsed_text()
	assert_bool(combo.contains("with Exposed") or combo.contains("wears off")).override_failure_message(combo).is_true()
	# Shred's two hits strip two pips.
	assert_str(combo).contains("Plating %d → %d" % [target.plating, target.plating - 2])
	assert_bool(_screen.outlook.combo_label.visible).is_true()


func test_breaking_plating_says_stagger() -> void:
	await _open(A.plated_fight())
	var target := _enemy("plated")
	target.plating = 1
	_screen.refresh()
	_screen.on_skill_pressed("strike")
	_screen.preview_target(target.id)
	assert_str(_screen.outlook.combo_label.get_parsed_text()).contains("Stagger!")


func test_the_outlook_changes_nothing() -> void:
	await _open(A.charger_fight())
	var before := T.snapshot(_screen.fight)
	var log_size := _screen.fight.log_lines.size()
	var tick := _screen.fight.timeline.current_tick
	for skill_id in ["strike", "shred", "heavy_strike"]:
		_screen.on_tile_hovered(skill_id, true)
		_screen.on_tile_hovered(skill_id, false)
		_screen.on_skill_pressed(skill_id)
		for c in _screen.fight.living(Combatant.Side.ENEMY):
			_screen.preview_target(c.id)
		_screen.on_cancel_pressed()
	_screen.on_wait_hovered(true)
	_screen.on_wait_hovered(false)
	assert_int(_screen.fight.log_lines.size()).is_equal(log_size)
	assert_int(_screen.fight.timeline.current_tick).is_equal(tick)
	assert_str(T.snapshot(_screen.fight)).is_equal(before)


func test_wait_is_there_even_when_every_skill_is_affordable() -> void:
	await _open(A.plated_fight())
	var actor := _screen.handler.actor()
	actor.energy_milli = actor.max_energy_milli
	_screen.refresh()
	assert_bool(_screen.wait_button.disabled).is_false()
	assert_str(UiTooltip.spec(_screen.wait_button)["body"]).contains("Bank Energy toward")
	_screen.on_wait_hovered(true)
	assert_bool(_screen.focus_card.visible).is_true()
	assert_str(_screen.focus_card.cost_label.text).is_equal("Free")
	_screen.on_wait_hovered(false)
	var count := _screen.fight.action_count
	_screen.on_wait_pressed()
	assert_int(_screen.fight.action_count).is_greater(count)
