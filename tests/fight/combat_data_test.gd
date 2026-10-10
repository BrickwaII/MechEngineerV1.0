extends GdUnitTestSuite
## The shipped tuning and enemy tables load and are usable.


func test_default_tuning_loads_and_validates() -> void:
	var tuning := CombatTuning.load_default()
	assert_object(tuning).is_not_null()
	assert_array(tuning.validate()).is_empty()


func test_enemy_tables_cover_every_defense_level() -> void:
	var table := EnemyTable.load_default()
	assert_object(table).is_not_null()
	assert_array(table.validate(CombatTuning.load_default())).is_empty()
	for level in range(FightRequest.MIN_DEFENSE_LEVEL, FightRequest.MAX_DEFENSE_LEVEL + 1):
		assert_bool(table.has_level(level)).is_true()


func test_validate_reports_broken_tuning() -> void:
	var tuning := CombatTuning.load_default()
	tuning.recharge_floor_milli_per_tick = 0
	tuning.player_skills.append("no_such_skill")
	assert_array(tuning.validate()).has_size(2)
