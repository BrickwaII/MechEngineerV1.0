extends GdUnitTestSuite
## The sandbox on the battle screen (S9): ScenarioBattle plays a scenario by
## hand with its kit, enemies and opening gauges, with the action-use panel.

const Helpers := preload("res://tests/ui/fight/fight_ui_helpers.gd")
const SANDBOX := "res://data/scenarios/sandbox_3v3.json"


func _battle(scenario: FightScenario = null, seed_value := 1) -> ScenarioBattle:
	var battle: ScenarioBattle = auto_free(load(ScenarioBattle.SCENE_PATH).instantiate())
	battle.scenario = scenario
	battle.fight_seed = seed_value
	battle.screen_tuning = Helpers.fast_tuning()
	add_child(battle)
	return battle


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func test_with_no_scenario_it_plays_the_sandbox_with_its_kit_and_enemies() -> void:
	var battle := _battle()
	assert_str(battle.scenario.scenario_name).is_equal(ScenarioFiles.load_scenario(SANDBOX).scenario_name)
	var screen := battle.service.screen
	assert_object(screen).is_not_null()
	var fight := screen.fight
	var resolved := ScenarioFiles.load_scenario(SANDBOX).resolve()
	var headless := resolved.start(1).fight
	assert_array(fight.combatants.map(func(c: Combatant) -> String: return c.id)).is_equal(
		headless.combatants.map(func(c: Combatant) -> String: return c.id))
	# The same opening gauges as the harness's fight on that seed.
	var opening := func(f: Fight) -> Array:
		return Array(f.log_lines).filter(func(line: String) -> bool: return line.contains("opening gauge"))
	assert_array(opening.call(fight)).is_not_empty()
	assert_array(opening.call(fight)).is_equal(opening.call(headless))
	for c in fight.combatants:
		if c.side == Combatant.Side.PLAYER:
			assert_array(c.skill_ids).is_equal(["strike", "shred", "heavy_strike", "brace"])
	assert_object(battle.share_panel.fight).is_same(fight)
	assert_object(battle.overlay.fight).is_same(fight)
	assert_bool(battle.overlay.visible).is_false()


func test_a_played_fight_ends_and_the_next_seed_banks_it_in_the_panel() -> void:
	var battle := _battle(null, 2)
	var screen := battle.service.screen
	await _frames(1)
	var guard := 0
	while not screen.fight.is_over() and guard < 2000:
		if screen.handler.is_player_turn():
			Helpers.play_turn_by_mouse(screen)
		else:
			await _frames(1)
		guard += 1
	await _frames(3)
	assert_object(battle.last_result).is_not_null()
	assert_bool(battle._end_bar.visible).is_true()
	assert_str(battle._end_label.text).contains("seed 2")
	var played := battle.share_panel.fight
	battle.start_fight(battle.fight_seed + 1)
	assert_int(battle.fight_seed).is_equal(3)
	assert_bool(battle._end_bar.visible).is_false()
	assert_int(battle.share_panel.session_fights).is_equal(1)
	assert_int(battle.share_panel.session.decisions).is_equal(FightSummary.of(played).squad.decisions)


func test_an_unplayable_scenario_says_why_and_starts_nothing() -> void:
	var s := ScenarioFiles.load_scenario(SANDBOX)
	s.kit.append("no_such_action")
	var battle := _battle(s)
	assert_object(battle.service.screen).is_null()
	assert_bool(battle._end_bar.visible).is_true()
	assert_str(battle._problem_label.text).contains("no_such_action")
