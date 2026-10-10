extends GdUnitTestSuite
## FightSceneService, headless: a contracts FightService played as a scene.

const Helpers := preload("res://tests/ui/fight/fight_ui_helpers.gd")

var _host: Node
var _service: FightSceneService
var _results: Array[FightResult] = []


func before_test() -> void:
	_host = auto_free(Node.new())
	add_child(_host)
	_service = FightSceneService.new(_host, Helpers.fast_tuning())
	_results.clear()
	_service.finished.connect(func(r: FightResult) -> void: _results.append(r))


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _play_to_the_end(screen: BattleScreen) -> void:
	var guard := 0
	while not screen.fight.is_over() and guard < 2000:
		if screen.handler.is_player_turn():
			Helpers.play_turn_by_mouse(screen)
		else:
			await _frames(1)
		guard += 1


func test_is_a_fight_service() -> void:
	assert_object(_service).is_instanceof(FightService)


func test_start_fight_opens_a_battle_screen_under_the_host() -> void:
	_service.start_fight(Helpers.request())
	assert_object(_service.screen).is_not_null()
	assert_object(_service.screen.get_parent()).is_same(_host)
	assert_array(_results).is_empty()


func test_finished_reports_the_fight_result_then_the_screen_goes() -> void:
	var request := Helpers.request()
	_service.start_fight(request)
	var screen := _service.screen
	await _frames(1)
	await _play_to_the_end(screen)
	assert_array(_results).is_empty()
	await _frames(2)
	assert_int(_results.size()).is_equal(1)
	var expected := _service.last_fight.result()
	assert_int(_results[0].outcome).is_equal(expected.outcome)
	assert_float(_results[0].grid_cost).is_equal(expected.grid_cost)
	assert_dict(_results[0].rewards).is_equal(expected.rewards)
	assert_object(_service.screen).is_null()
	assert_bool(is_instance_valid(screen)).is_false()


func test_the_same_play_gives_the_auto_service_result() -> void:
	var request := Helpers.request()
	_service.start_fight(request)
	await _frames(1)
	await _play_to_the_end(_service.screen)
	await _frames(2)
	# AutoFightService plays SimpleFightPolicy for the squad, as the helper does.
	var auto := AutoFightService.new().resolve(request)
	assert_int(_results[0].outcome).is_equal(auto.outcome)
	assert_float(_results[0].grid_cost).is_equal(auto.grid_cost)


func test_the_seed_matches_auto_fight_service() -> void:
	var request := Helpers.request(3)
	assert_int(_service.seed_for(request)).is_equal(AutoFightService.new().seed_for(request))
	_service.fixed_seed = 99
	assert_int(_service.seed_for(request)).is_equal(99)


func test_an_invalid_request_finishes_with_defeat_on_a_later_frame() -> void:
	var empty: Array[SquadMemberSummary] = []
	_service.start_fight(FightRequest.new(FightRequest.Kind.ATTACK, "t", 1, empty))
	assert_array(_results).is_empty()
	await _frames(3)
	assert_int(_results.size()).is_equal(1)
	assert_bool(_results[0].is_victory()).is_false()


func test_a_second_fight_runs_after_the_first() -> void:
	_service.start_fight(Helpers.request())
	await _frames(1)
	await _play_to_the_end(_service.screen)
	await _frames(2)
	_service.start_fight(Helpers.request(2))
	assert_object(_service.screen).is_not_null()
	await _frames(1)
	await _play_to_the_end(_service.screen)
	await _frames(2)
	assert_int(_results.size()).is_equal(2)
