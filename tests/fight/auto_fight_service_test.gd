extends GdUnitTestSuite

const H := preload("res://tests/fight/fight_test_helpers.gd")


func _request(level: int, territory := "t") -> FightRequest:
	return FightRequest.new(FightRequest.Kind.ATTACK, territory, level, StubSquadProvider.new().get_squad())


func test_is_a_fight_service() -> void:
	assert_object(AutoFightService.new()).is_instanceof(FightService)


func test_emits_finished_on_the_next_frame_not_during_start_fight() -> void:
	var service := AutoFightService.new()
	var received: Array[FightResult] = []
	service.finished.connect(func(result: FightResult) -> void: received.append(result))
	service.start_fight(_request(0))
	assert_array(received).is_empty()
	await get_tree().process_frame
	assert_array(received).has_size(1)


func test_emits_finished_once_per_fight() -> void:
	var service := AutoFightService.new()
	var count := [0]
	service.finished.connect(func(_result: FightResult) -> void: count[0] += 1)
	service.start_fight(_request(1))
	service.start_fight(_request(5))
	for i in 3:
		await get_tree().process_frame
	assert_int(count[0]).is_equal(2)


func test_same_request_gives_the_same_result() -> void:
	var service := AutoFightService.new()
	var a := service.resolve(_request(3))
	var log_a := service.last_fight.log_text()
	var b := service.resolve(_request(3))
	assert_int(b.outcome).is_equal(a.outcome)
	assert_float(b.grid_cost).is_equal(a.grid_cost)
	assert_str(service.last_fight.log_text()).is_equal(log_a)


func test_result_is_the_headless_runner_with_enemies_played_by_intent() -> void:
	var service := AutoFightService.new()
	var request := _request(2)
	var result := service.resolve(request)
	var fight := HeadlessFightRunner.run(request, service.seed_for(request), SimpleFightPolicy.new(), IntentFightPolicy.new())
	assert_int(result.outcome).is_equal(fight.result().outcome)
	assert_float(result.grid_cost).is_equal(fight.result().grid_cost)


func test_fixed_seed_overrides_the_request_seed() -> void:
	var service := AutoFightService.new()
	service.fixed_seed = 77
	assert_int(service.seed_for(_request(1, "a"))).is_equal(77)
	assert_int(service.seed_for(_request(1, "b"))).is_equal(77)


func test_the_stub_squad_wins_the_easiest_fight() -> void:
	assert_bool(AutoFightService.new().resolve(_request(0)).is_victory()).is_true()


func test_an_invalid_request_is_a_defeat() -> void:
	var empty: Array[SquadMemberSummary] = []
	var request := FightRequest.new(FightRequest.Kind.ATTACK, "t", 9, empty)
	assert_bool(AutoFightService.new().resolve(request).is_victory()).is_false()
