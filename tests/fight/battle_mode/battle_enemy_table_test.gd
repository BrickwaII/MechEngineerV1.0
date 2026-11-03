extends GdUnitTestSuite
## BattleEnemyTable: a fight fields the encounter at its scaling.

const B := preload("res://tests/fight/battle_mode/battle_mode_test_helpers.gd")
const H := preload("res://tests/fight/fight_test_helpers.gd")


func _encounter() -> BattleEncounter:
	var e := BattleEncounter.new()
	e.enemy_ids = ["boss_a", "red_a", "red_a"]
	e.scaling = {"hp_percent": 200, "attack_percent": 150, "defense_percent": 300, "speed_bonus": 2}
	e.boss_scaling = {"hp_percent": 50, "attack_percent": 100, "defense_percent": 100, "speed_bonus": 0}
	return e


func test_fields_exactly_the_encounter_whatever_the_seed() -> void:
	var table := BattleEnemyTable.for_encounter(B.table(), _encounter())
	var squad: Array[SquadMemberSummary] = [H.member("a", H.stats(40, 8, 3, 6, 10))]
	for s in 5:
		var fight := Fight.new(H.request(squad), s, null, table)
		var ids := fight.combatants.filter(func(c: Combatant) -> bool: return c.side == Combatant.Side.ENEMY).map(
			func(c: Combatant) -> String: return c.id)
		assert_array(ids).is_equal(["boss_a#1", "red_a#1", "red_a#2"])


func test_scales_normal_enemies_and_the_boss_apart() -> void:
	var table := BattleEnemyTable.for_encounter(B.table(), _encounter())
	var req := H.request([H.member("a", H.stats(40, 8, 3, 6, 10))])
	var red := table.stats_for("red_a", req)
	assert_int(red.hp).is_equal(20)
	assert_int(red.attack).is_equal(5)
	assert_int(red.defense).is_equal(3)
	assert_int(red.speed).is_equal(7)
	var boss := table.stats_for("boss_a", req)
	assert_int(boss.hp).is_equal(20)
	assert_int(boss.speed).is_equal(4)
