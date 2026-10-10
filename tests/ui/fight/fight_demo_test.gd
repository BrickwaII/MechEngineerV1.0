extends GdUnitTestSuite
## The runnable demo: draft -> fight -> result text.

const Helpers := preload("res://tests/ui/fight/fight_ui_helpers.gd")
const SCENE := "res://ui/fight/fight_demo.tscn"


func test_draft_then_fight_then_result() -> void:
	var runner := scene_runner(SCENE)
	await runner.simulate_frames(2)
	var demo := runner.scene()
	var draft: DraftScreen = demo.draft
	assert_object(draft).is_not_null()
	var squad_size := draft.picker.squad_size()
	for i in squad_size:
		draft.toggle(draft.picker.bots()[i].id)
	draft.start_button.pressed.emit()
	await runner.simulate_frames(1)
	var screen: BattleScreen = demo.service.screen
	assert_object(screen).is_not_null()
	assert_int(screen.fight.request.squad.size()).is_equal(squad_size)
	screen.enemy_turn_delay = 0.0
	var guard := 0
	while not screen.fight.is_over() and guard < 2000:
		if screen.handler.is_player_turn():
			Helpers.play_turn_by_mouse(screen)
		else:
			await runner.simulate_frames(1)
		guard += 1
	await runner.simulate_frames(3)
	assert_object(demo.last_result).is_not_null()
	assert_bool(demo.result_panel.visible).is_true()
	assert_str(demo.result_label.text).starts_with("VICTORY" if demo.last_result.is_victory() else "DEFEAT")


func test_describe_lists_outcome_cost_and_rewards() -> void:
	var demo_script: GDScript = load("res://ui/fight/fight_demo.gd")
	var rewards: Dictionary[String, int] = {"energy": 6, "material": 3}
	var text: String = demo_script.describe(FightResult.new(FightResult.Outcome.VICTORY, 6.0, rewards))
	assert_str(text).is_equal("VICTORY\nGrid cost: 6.0%\nRewards: energy 6, material 3")
	text = demo_script.describe(FightResult.new(FightResult.Outcome.DEFEAT, 4.5))
	assert_str(text).is_equal("DEFEAT\nGrid cost: 4.5%\nRewards: none")
