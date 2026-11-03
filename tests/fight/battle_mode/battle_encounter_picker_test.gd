extends GdUnitTestSuite
## BattleEncounterPicker: deterministic draws that follow the curve.

const B := preload("res://tests/fight/battle_mode/battle_mode_test_helpers.gd")


func _pick(n: int, t: BattleModeTuning, seed_value := 1, length_id := "endless") -> BattleEncounter:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return BattleEncounterPicker.pick(n, t.length(length_id), t, B.table(), rng)


func test_same_seed_same_encounter() -> void:
	var t := B.tuning([{"count": 3, "types": 2, "factions": 2}])
	for s in 20:
		assert_array(_pick(1, t, s).enemy_ids).is_equal(_pick(1, t, s).enemy_ids)


func test_seeds_vary_the_draw() -> void:
	var t := B.tuning([{"count": 3, "types": 2, "factions": 2}])
	var seen := {}
	for s in 20:
		seen[str(_pick(1, t, s).enemy_ids)] = true
	assert_int(seen.size()).is_greater(1)


func test_count_types_and_tiers_follow_the_row() -> void:
	var t := B.tuning([{"count": 3, "types": 2, "factions": 1}])
	var table := B.table()
	for s in 30:
		var e := _pick(1, t, s)
		assert_int(e.enemy_ids.size()).is_equal(3)
		assert_int(e.distinct_types()).is_equal(2)
		for id in e.enemy_ids:
			assert_str(str(table.enemies[id].tier)).is_equal("beginner")
			assert_bool(bool(table.enemies[id].get("boss", false))).is_false()


func test_one_faction_rows_draw_from_one_faction() -> void:
	var t := B.tuning([{"count": 2, "types": 1, "factions": 1}])
	var table := B.table()
	for s in 30:
		var e := _pick(1, t, s)
		var factions := {}
		for id in e.enemy_ids:
			factions[BattleEncounterPicker.faction_of(table.enemies[id])] = true
		assert_int(factions.size()).is_equal(1)
		assert_int(e.factions.size()).is_equal(1)


func test_too_few_kinds_widens_to_more_factions() -> void:
	# The generic roster has one beginner; three kinds need more factions.
	var t := B.tuning([{"count": 3, "types": 3, "factions": 1}])
	for s in 30:
		assert_int(_pick(1, t, s).distinct_types()).is_equal(3)


func test_fast_kinds_are_fielded() -> void:
	# Only the red faction has a fast beginner, so draw from every faction.
	var t := B.tuning([{"count": 2, "types": 2, "factions": 3, "fast": 1}])
	var table := B.table()
	for s in 30:
		var e := _pick(1, t, s)
		var fast := e.enemy_ids.filter(func(id: String) -> bool: return int(table.enemies[id].speed) >= 9)
		assert_int(fast.size()).override_failure_message("seed %d: %s" % [s, e.enemy_ids]).is_greater_equal(1)


func test_speed_bonus_counts_toward_fast() -> void:
	# Everything at speed 5 + 4 is fast.
	var t := B.tuning([{"count": 2, "types": 2, "factions": 3, "fast": 2, "speed_bonus": 4}])
	var e := _pick(1, t)
	assert_int(e.distinct_types()).is_equal(2)
	assert_int(int(e.scaling.speed_bonus)).is_equal(4)


func test_archetype_enemies_join_the_pools_from_their_fight() -> void:
	var t := B.tuning([{"count": 6, "types": 6, "factions": 3}])
	for s in 10:
		assert_bool("charger" in _pick(1, t, s).enemy_ids).is_false()
	var joined := false
	for s in 10:
		joined = joined or "charger" in _pick(2, t, s).enemy_ids
	assert_bool(joined).is_true()


func test_elite_shifts_tiers_up_adds_a_kind_and_keeps_the_count() -> void:
	var t := B.tuning([{"count": 3, "types": 1, "factions": 2}], {"elite_every": 2})
	var table := B.table()
	var e := _pick(2, t)
	assert_int(e.kind).is_equal(BattleEncounter.Kind.ELITE)
	assert_int(e.enemy_ids.size()).is_equal(3)
	assert_int(e.distinct_types()).is_equal(2)
	assert_int(int(e.scaling.hp_percent)).is_equal(150)
	for id in e.enemy_ids:
		assert_bool(str(table.enemies[id].tier) in ["medium", "advanced"]).is_true()
	assert_int(_pick(1, t).kind).is_equal(BattleEncounter.Kind.NORMAL)


func test_bosses_come_in_order_with_escorts() -> void:
	var t := B.tuning([{"count": 3, "types": 2}])
	# endless: a boss every 4th fight; the order repeats.
	var first := _pick(4, t)
	assert_int(first.kind).is_equal(BattleEncounter.Kind.BOSS)
	assert_str(first.enemy_ids[0]).is_equal("boss_a")
	assert_int(first.enemy_ids.size()).is_equal(2)
	# 50% of the row's hp, which endless growth has raised to 110% by fight 4.
	assert_int(int(first.boss_scaling.hp_percent)).is_equal(55)
	assert_str(_pick(8, t).enemy_ids[0]).is_equal("boss_b")
	assert_str(_pick(12, t).enemy_ids[0]).is_equal("boss_a")


func test_gauntlet_boss_fights_come_from_the_length() -> void:
	var t := B.tuning()
	assert_int(_pick(3, t, 1, "gauntlet").kind).is_equal(BattleEncounter.Kind.BOSS)
	assert_int(_pick(2, t, 1, "gauntlet").kind).is_equal(BattleEncounter.Kind.NORMAL)
	assert_int(_pick(4, t, 1, "gauntlet").kind).is_equal(BattleEncounter.Kind.NORMAL)


func test_shipped_curve_asks_more_questions_later() -> void:
	# The deep dive's rule: more kinds at once later in a run, not just more HP.
	var t := BattleModeTuning.load_default()
	var table := EnemyTable.load_default()
	var length := t.length("endless")
	var early := 0
	var late := 0
	for s in 10:
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		early += BattleEncounterPicker.pick(1, length, t, table, rng).distinct_types()
		late += BattleEncounterPicker.pick(14, length, t, table, rng).distinct_types()
	assert_int(late).is_greater(early)
