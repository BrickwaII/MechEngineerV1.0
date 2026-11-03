extends GdUnitTestSuite
## BattleModeFlow: setup, fights on the battle screen, the readout bar, the
## summary, the CSV, leaving, and the main menu's tile.

const Helpers := preload("res://tests/ui/fight/fight_ui_helpers.gd")
const CSV := "user://test_battle_mode_flow"
const MENU := "res://ui/main/main.tscn"

var _runner: GdUnitSceneRunner


func after_test() -> void:
	for f in ["fights.csv", "runs.csv"]:
		DirAccess.remove_absolute(CSV.path_join(f))
	get_tree().paused = false


func _flow(p_tuning: BattleModeTuning = null) -> BattleModeFlow:
	var flow := BattleModeFlow.new()
	flow.run_seed = 5
	flow.csv_folder = CSV
	flow.fight_screen_tuning = Helpers.fast_tuning()
	flow.variants_source = func() -> FightVariants: return FightVariants.defaults()
	if p_tuning != null:
		flow.tuning = p_tuning
	_runner = scene_runner(auto_free(flow))
	return flow


## Plays the battle on screen to its end, the squad by SimpleFightPolicy's
## choices sent as commands, the enemies by the screen itself.
func _play_battle(flow: BattleModeFlow) -> void:
	var screen := flow.battle_screen
	var policy := SimpleFightPolicy.new()
	var rng := RandomNumberGenerator.new()
	var guard := 0
	while flow.stage == BattleModeFlow.Stage.FIGHT and guard < 3000:
		guard += 1
		if is_instance_valid(screen) and not screen.fight.is_over() and screen.handler.is_player_turn():
			var action := policy.choose(screen.fight, screen.handler.actor(), rng)
			screen.send(FightCommand.select_skill(action.skill_id))
			screen.send(FightCommand.select_target(action.target_id))
		await _runner.simulate_frames(1)
	await _runner.simulate_frames(2)


func test_setup_offers_every_length_and_squad() -> void:
	var flow := _flow()
	await _runner.simulate_frames(2)
	assert_int(flow.stage).is_equal(BattleModeFlow.Stage.SETUP)
	var t := BattleModeTuning.load_default()
	assert_int(flow.setup_screen.length_cards.size()).is_equal(t.lengths.size())
	assert_int(flow.setup_screen.squad_cards.size()).is_equal(t.squads.size() + 1)
	flow.setup_screen.length_cards["endless"].pressed.emit()
	flow.setup_screen.squad_cards[BattleModeSetup.DRAFT].pressed.emit()
	assert_str(flow.setup_screen.length_id).is_equal("endless")
	assert_str(flow.setup_screen.squad_id).is_equal(BattleModeSetup.DRAFT)
	assert_bool(flow.setup_screen.length_cards["endless"].button_pressed).is_true()


func test_a_preset_starts_the_first_fight_with_the_encounter() -> void:
	var flow := _flow()
	await _runner.simulate_frames(2)
	flow.setup_screen.start()
	await _runner.simulate_frames(2)
	assert_int(flow.stage).is_equal(BattleModeFlow.Stage.FIGHT)
	assert_object(flow.battle_screen).is_not_null()
	var enemies: Array = flow.battle_screen.fight.combatants.filter(
		func(c: Combatant) -> bool: return c.side == Combatant.Side.ENEMY).map(
		func(c: Combatant) -> String: return c.id.get_slice("#", 0))
	assert_array(enemies).is_equal(Array(flow.run.encounter.enemy_ids))
	assert_object(flow.run.fight).is_same(flow.battle_screen.fight)


func test_a_won_fight_shows_the_readout_with_its_numbers_then_the_next_fight() -> void:
	var flow := _flow()
	await _runner.simulate_frames(2)
	flow.setup_screen.start()
	await _runner.simulate_frames(2)
	var fight := flow.battle_screen.fight
	await _play_battle(flow)
	assert_int(flow.stage).is_equal(BattleModeFlow.Stage.READOUT)
	var record: BattleFightRecord = flow.run.records[0]
	assert_bool(record.victory).is_true()
	var squad_tags := fight.action_tags.filter(func(t: String) -> bool:
		return fight.combatant(t.get_slice(":", 0)).side == Combatant.Side.PLAYER)
	assert_int(record.turns).is_equal(squad_tags.size())
	assert_object(flow.readout_page.find_child("FightLine1", true, false)).is_not_null()
	flow.readout.skip()
	assert_str(flow.continue_button.text).is_equal("NEXT FIGHT")
	flow.continue_button.pressed.emit()
	await _runner.simulate_frames(2)
	assert_int(flow.stage).is_equal(BattleModeFlow.Stage.FIGHT)
	assert_int(flow.run.fight_number()).is_equal(2)


## The screen's numbers are the headless loop's for the same choices.
func test_a_played_fight_records_what_the_sim_does() -> void:
	var flow := _flow()
	await _runner.simulate_frames(2)
	flow.setup_screen.start()
	await _runner.simulate_frames(2)
	await _play_battle(flow)
	var sim := BattleModeRun.create(BattleModeRun.preset_squad(BattleModeTuning.load_default().squads[0].id),
		"gauntlet", 5, FightVariants.defaults())
	var simulated := sim.play_fight(SimpleFightPolicy.new())
	assert_array(flow.run.records[0].csv_row("x")).is_equal(simulated.csv_row("x"))


func test_a_lost_run_ends_on_the_summary_and_writes_the_csv() -> void:
	var t := BattleModeTuning.load_default()
	for row in t.curve:
		row.hp_percent = 3000
		row.attack_percent = 1000
	var flow := _flow(t)
	await _runner.simulate_frames(2)
	flow.setup_screen.start()
	await _runner.simulate_frames(2)
	await _play_battle(flow)
	assert_bool(flow.run.is_over()).is_true()
	assert_int(flow.csv_result).is_equal(OK)
	flow.readout.skip()
	assert_str(flow.continue_button.text).is_equal("SEE THE RUN")
	flow.continue_button.pressed.emit()
	await _runner.simulate_frames(2)
	assert_int(flow.stage).is_equal(BattleModeFlow.Stage.OVER)
	assert_str((flow.summary_screen.find_child("Outcome", true, false) as Label).text).contains("FELL AT FIGHT 1")
	var rows := FileAccess.get_file_as_string(CSV.path_join("fights.csv")).strip_edges().split("\n")
	assert_int(rows.size()).is_equal(2)
	flow.summary_screen.again_button.pressed.emit()
	await _runner.simulate_frames(2)
	assert_int(flow.stage).is_equal(BattleModeFlow.Stage.SETUP)


func test_esc_in_a_battle_asks_then_leaves() -> void:
	var flow := _flow()
	var left := [false]
	flow.exit_requested.connect(func() -> void: left[0] = true)
	await _runner.simulate_frames(2)
	flow.setup_screen.start()
	await _runner.simulate_frames(2)
	flow.go_home()
	assert_object(flow.pause_menu).is_not_null()
	assert_bool(flow.pause_menu.is_confirming()).is_true()
	assert_bool(get_tree().paused).is_true()
	flow.pause_menu.home_requested.emit()
	assert_bool(left[0]).is_true()
	assert_bool(get_tree().paused).is_false()
	assert_bool(flow.run.is_over()).is_true()


func test_home_on_setup_leaves_at_once() -> void:
	var flow := _flow()
	var left := [false]
	flow.exit_requested.connect(func() -> void: left[0] = true)
	await _runner.simulate_frames(2)
	flow.setup_screen.home_button.pressed.emit()
	assert_bool(left[0]).is_true()
	assert_object(flow.pause_menu).is_null()


func test_the_draft_choice_opens_the_draft_then_fights_with_the_picks() -> void:
	var flow := _flow()
	await _runner.simulate_frames(2)
	flow.start("gauntlet", BattleModeSetup.DRAFT)
	await _runner.simulate_frames(2)
	assert_int(flow.stage).is_equal(BattleModeFlow.Stage.DRAFT)
	var bots := flow.draft_screen.picker.bots()
	for i in BotTuning.load_default().squad_size:
		flow.draft_screen.toggle(bots[i].id)
	flow.draft_screen.start()
	await _runner.simulate_frames(2)
	assert_int(flow.stage).is_equal(BattleModeFlow.Stage.FIGHT)
	assert_str(flow.run.squad_label).is_equal("draft")
	assert_str(flow.run.squad.get_fielded()[0].id).is_equal(bots[0].id)


func test_the_main_menu_tile_opens_battle_mode_and_comes_back() -> void:
	var menu: MainMenu = load(MENU).instantiate()
	menu.runs_root = "user://battle_mode_menu_runs"
	menu.show_whats_new = false
	var runner := scene_runner(auto_free(menu))
	await runner.simulate_frames(2)
	menu.battle_mode_button.pressed.emit()
	await runner.simulate_frames(2)
	assert_object(menu.battle_mode).is_not_null()
	assert_bool(menu.menu.visible).is_false()
	menu.battle_mode.setup_screen.home_button.pressed.emit()
	await runner.simulate_frames(2)
	assert_object(menu.battle_mode).is_null()
	assert_bool(menu.menu.visible).is_true()
