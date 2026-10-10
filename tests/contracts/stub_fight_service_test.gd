extends GdUnitTestSuite


func _request(level: int) -> FightRequest:
	return FightRequest.new(FightRequest.Kind.ATTACK, "t", level, StubSquadProvider.new().get_squad())


func test_is_a_fight_service() -> void:
	assert_object(StubFightService.new()).is_instanceof(FightService)


func test_wins_at_defense_level_3_or_lower_and_loses_above() -> void:
	var service := StubFightService.new()
	var outcomes := range(0, 6).map(func(level: int) -> bool: return service.resolve(_request(level)).is_victory())
	assert_array(outcomes).contains_exactly([true, true, true, true, false, false])


func test_charges_4_plus_2_per_defense_level_in_grid_percent() -> void:
	var service := StubFightService.new()
	var costs := range(0, 6).map(func(level: int) -> float: return service.resolve(_request(level)).grid_cost)
	assert_array(costs).contains_exactly([4.0, 6.0, 8.0, 10.0, 12.0, 14.0])


func test_victory_rewards_energy_and_material_and_defeat_rewards_nothing() -> void:
	var service := StubFightService.new()
	assert_dict(service.resolve(_request(1)).rewards).contains_keys([FightResult.ENERGY, FightResult.MATERIAL])
	assert_dict(service.resolve(_request(5)).rewards).is_empty()


func test_defend_fights_follow_the_same_rule() -> void:
	var request := FightRequest.new(FightRequest.Kind.DEFEND, "t", 4, StubSquadProvider.new().get_squad())
	assert_bool(StubFightService.new().resolve(request).is_victory()).is_false()


func test_emits_finished_on_the_next_frame_not_during_start_fight() -> void:
	var service := StubFightService.new()
	var received: Array[FightResult] = []
	service.finished.connect(func(result: FightResult) -> void: received.append(result))
	service.start_fight(_request(2))
	assert_array(received).is_empty()
	await get_tree().process_frame
	assert_array(received).has_size(1)
	assert_bool(received[0].is_victory()).is_true()
	assert_float(received[0].grid_cost).is_equal(8.0)


func test_emits_finished_once_per_fight() -> void:
	var service := StubFightService.new()
	var count := [0]
	service.finished.connect(func(_result: FightResult) -> void: count[0] += 1)
	service.start_fight(_request(1))
	service.start_fight(_request(5))
	for i in 3:
		await get_tree().process_frame
	assert_int(count[0]).is_equal(2)
