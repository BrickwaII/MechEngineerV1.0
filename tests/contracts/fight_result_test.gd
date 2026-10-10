extends GdUnitTestSuite


func test_holds_its_fields() -> void:
	var result := FightResult.new(FightResult.Outcome.VICTORY, 6.0, {FightResult.ENERGY: 10})
	assert_bool(result.is_victory()).is_true()
	assert_float(result.grid_cost).is_equal(6.0)
	assert_dict(result.rewards).is_equal({"energy": 10})


func test_resource_ids_are_energy_and_material() -> void:
	assert_str(FightResult.ENERGY).is_equal("energy")
	assert_str(FightResult.MATERIAL).is_equal("material")


func test_defeat_is_not_victory() -> void:
	assert_bool(FightResult.new(FightResult.Outcome.DEFEAT).is_victory()).is_false()


func test_default_rewards_are_not_shared_between_results() -> void:
	var first := FightResult.new()
	first.rewards[FightResult.ENERGY] = 1
	assert_dict(FightResult.new().rewards).is_empty()
