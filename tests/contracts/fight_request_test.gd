extends GdUnitTestSuite


func _squad() -> Array[SquadMemberSummary]:
	return StubSquadProvider.new().get_squad()


func test_holds_its_fields() -> void:
	var squad := _squad()
	var request := FightRequest.new(FightRequest.Kind.DEFEND, "t_harbor", 2, squad)
	assert_int(request.kind).is_equal(FightRequest.Kind.DEFEND)
	assert_str(request.territory_id).is_equal("t_harbor")
	assert_int(request.defense_level).is_equal(2)
	assert_array(request.squad).is_same(squad)


func test_is_valid_for_every_defense_level_from_0_to_5() -> void:
	for level in range(0, 6):
		assert_bool(FightRequest.new(FightRequest.Kind.ATTACK, "t", level, _squad()).is_valid()).is_true()


func test_is_invalid_outside_0_to_5() -> void:
	assert_bool(FightRequest.new(FightRequest.Kind.ATTACK, "t", -1, _squad()).is_valid()).is_false()
	assert_bool(FightRequest.new(FightRequest.Kind.ATTACK, "t", 6, _squad()).is_valid()).is_false()


func test_is_invalid_without_a_territory_or_squad() -> void:
	assert_bool(FightRequest.new(FightRequest.Kind.ATTACK, "", 1, _squad()).is_valid()).is_false()
	assert_bool(FightRequest.new(FightRequest.Kind.ATTACK, "t", 1, []).is_valid()).is_false()
