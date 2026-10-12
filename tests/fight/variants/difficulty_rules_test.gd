extends GdUnitTestSuite
## difficulty-curve: the tuned option's tier table, enemy counts and scaling;
## flat is the old rule. TODO(decision: difficulty-targets).

const H := preload("res://tests/fight/fight_test_helpers.gd")
const V := preload("res://tests/fight/variants/variant_test_helpers.gd")

## A region of act 1 (data/combat/factions.json).
const ACT1_REGION := "ballard"


func _params(t: CombatTuning) -> Dictionary:
	return t.variants.params_by_option[FightVariants.DIFFICULTY_CURVE][FightVariants.DIFFICULTY_TUNED]


func test_flat_is_the_old_rule() -> void:
	var t := V.tuning_with(FightVariants.DIFFICULTY_CURVE, FightVariants.DIFFICULTY_FLAT)
	var factions := FactionTable.load_default()
	for level in 6:
		assert_str(DifficultyRules.tier_for(factions, "act1", level, t)).is_equal(factions.tier_for("act1", level))
	assert_int(DifficultyRules.count_for(4, t)).is_equal(-1)
	var stats := H.stats(30, 8, 4, 5, 10)
	assert_object(DifficultyRules.scaled(stats, "act1", "advanced", t)).is_same(stats)


func test_tuned_reads_its_tier_table_and_counts() -> void:
	var t := V.tuning_with(FightVariants.DIFFICULTY_CURVE, FightVariants.DIFFICULTY_TUNED)
	var p := _params(t)
	for level in 6:
		assert_str(DifficultyRules.tier_for(FactionTable.load_default(), "act3", level, t)).is_equal(p.tier_by_act.act3[level])
		assert_int(DifficultyRules.count_for(level, t)).is_equal(int(p.count_by_level[level]))


func test_tuned_scales_by_act_and_tier() -> void:
	var t := V.tuning_with(FightVariants.DIFFICULTY_CURVE, FightVariants.DIFFICULTY_TUNED)
	var p := _params(t)
	var stats := H.stats(100, 10, 10, 5, 10)
	var s := DifficultyRules.scaled(stats, "act2", "advanced", t)
	var a: Dictionary = p.scaling.act2
	var b: Dictionary = p.tier_scaling.advanced
	assert_int(s.hp).is_equal(roundi(100 * float(a.hp_percent) * float(b.hp_percent) / 10000.0))
	assert_int(s.attack).is_equal(roundi(10 * float(a.attack_percent) * float(b.attack_percent) / 10000.0))
	assert_int(s.speed).is_equal(5)
	assert_str(DifficultyRules.scaling_key(FactionTable.load_default(), ACT1_REGION)).is_equal("act1")
	assert_str(DifficultyRules.scaling_key(FactionTable.load_default(), "boss")).is_equal("boss")


func test_a_tuned_fight_fields_the_tuned_enemies() -> void:
	var t := V.tuning_with(FightVariants.DIFFICULTY_CURVE, FightVariants.DIFFICULTY_TUNED)
	var p := _params(t)
	var squad: Array[SquadMemberSummary] = [H.member("a", H.stats(30, 6, 2, 6, 10))]
	var level := 4
	var request := FightRequest.new(FightRequest.Kind.ATTACK, ACT1_REGION, level, squad)
	var table := EnemyTable.load_default()
	var fight := Fight.new(request, 7, t, table)
	var enemies := fight.combatants.filter(func(c: Combatant) -> bool: return c.side == Combatant.Side.ENEMY)
	assert_int(enemies.size()).is_equal(int(p.count_by_level[level]))
	var tier: String = p.tier_by_act.act1[level]
	for e: Combatant in enemies:
		var enemy_id := e.id.get_slice("#", 0)
		assert_str(str(table.enemies[enemy_id].tier)).is_equal(tier)
		assert_int(e.max_hp).is_equal(DifficultyRules.scaled(table.stats_of(enemy_id), "act1", tier, t).hp)
