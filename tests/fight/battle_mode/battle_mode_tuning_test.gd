extends GdUnitTestSuite
## BattleModeTuning: the shipped file, the curve lookup and validation.

const B := preload("res://tests/fight/battle_mode/battle_mode_test_helpers.gd")


func test_shipped_file_is_valid() -> void:
	var t := BattleModeTuning.load_default()
	assert_array(t.validate(EnemyTable.load_default())).is_empty()
	assert_bool(t.lengths.has("gauntlet")).is_true()
	assert_bool(t.lengths.has("endless")).is_true()
	assert_bool(t.length("endless").is_endless()).is_true()


func test_shipped_gauntlet_is_ten_fights_with_bosses_at_five_and_ten() -> void:
	var g := BattleModeTuning.load_default().length("gauntlet")
	assert_int(g.fights).is_equal(10)
	for n in range(1, 11):
		assert_bool(g.is_boss(n)).override_failure_message("fight %d" % n).is_equal(n == 5 or n == 10)


func test_every_preset_squad_fields_a_full_valid_squad() -> void:
	var t := BattleModeTuning.load_default()
	for p in t.squads:
		var squad := BattleModeRun.preset_squad(p.id, t)
		assert_object(squad).is_not_null()
		assert_bool(squad.is_valid()).is_true()
		assert_int(squad.get_fielded().size()).is_equal(BotTuning.load_default().squad_size)


func test_row_for_picks_the_last_row_started() -> void:
	var t := B.tuning([{"count": 2}, {"count": 3}, {"count": 4, "types": 2}])
	assert_int(t.row_for(1).count).is_equal(2)
	assert_int(t.row_for(2).count).is_equal(3)
	assert_int(t.row_for(3).count).is_equal(4)


func test_endless_growth_past_the_last_row_is_stepped_and_capped() -> void:
	var t := B.tuning([{"count": 2}])
	# every 2 fights: +10% hp, +1 count (max 4), +1 type (max 3), +1 speed (max 2)
	assert_int(t.row_for(2).hp_percent).is_equal(100)
	assert_int(t.row_for(3).hp_percent).is_equal(110)
	assert_int(t.row_for(3).count).is_equal(3)
	assert_int(t.row_for(5).hp_percent).is_equal(120)
	assert_int(t.row_for(11).count).is_equal(4)
	assert_int(t.row_for(11).types).is_equal(3)
	assert_int(t.row_for(11).speed_bonus).is_equal(2)


func test_row_for_returns_a_copy() -> void:
	var t := B.tuning()
	t.row_for(1).count = 99
	assert_int(t.row_for(1).count).is_equal(2)


func test_tier_up_stops_at_the_top() -> void:
	var t := B.tuning()
	assert_str(t.tier_up("beginner")).is_equal("medium")
	assert_str(t.tier_up("advanced")).is_equal("advanced")


func test_validate_reports_bad_rows_and_bosses() -> void:
	var t := B.tuning([{"types": 3, "tiers": ["legendary"], "fast": 5}], {"boss": {"order": ["nobody"]}})
	var problems := t.validate(B.table())
	assert_bool(problems.any(func(p: String) -> bool: return "types must be" in p)).is_true()
	assert_bool(problems.any(func(p: String) -> bool: return "unknown tier legendary" in p)).is_true()
	assert_bool(problems.any(func(p: String) -> bool: return "fast must be" in p)).is_true()
	assert_bool(problems.any(func(p: String) -> bool: return "boss nobody" in p)).is_true()


func test_validate_reports_missing_keys() -> void:
	var t := BattleModeTuning.from_dict({})
	assert_bool(t.validate(null).any(func(p: String) -> bool: return "missing 'lengths'" in p)).is_true()
