extends GdUnitTestSuite
## Enemies come from data/combat/enemy_tables.json by defense level.

const H := preload("res://tests/fight/fight_test_helpers.gd")

var _table: EnemyTable


func before_test() -> void:
	_table = EnemyTable.load_default()


func _enemy_ids(level: int, seed_value: int) -> Array[String]:
	var squad := StubSquadProvider.new().get_squad()
	var fight := Fight.new(H.request(squad, level), seed_value)
	var ids: Array[String] = []
	for c in fight.combatants:
		if c.side == Combatant.Side.ENEMY:
			ids.append(c.id)
	return ids


func test_each_level_fields_its_count_from_its_pool() -> void:
	for level in range(FightRequest.MIN_DEFENSE_LEVEL, FightRequest.MAX_DEFENSE_LEVEL + 1):
		var entry: Dictionary = _table.levels[level]
		var ids := _enemy_ids(level, 3)
		assert_int(ids.size()).is_equal(int(entry.count))
		for id in ids:
			assert_array(entry.pool).contains([id.get_slice("#", 0)])


func test_enemies_take_their_stats_from_the_table() -> void:
	var squad := StubSquadProvider.new().get_squad()
	var fight := Fight.new(H.request(squad, 0), 1)
	var drone := fight.combatant("scrap_drone#1")
	var def: Dictionary = _table.enemies["scrap_drone"]
	assert_int(drone.hp).is_equal(int(def.hp))
	assert_int(drone.stats.attack).is_equal(int(def.attack))
	assert_int(drone.stats.speed).is_equal(int(def.speed))
	assert_array(drone.skill_ids).contains_exactly(def.skills)


func test_same_seed_fields_the_same_enemies() -> void:
	for level in range(FightRequest.MIN_DEFENSE_LEVEL, FightRequest.MAX_DEFENSE_LEVEL + 1):
		assert_array(_enemy_ids(level, 42)).is_equal(_enemy_ids(level, 42))


func test_seed_changes_the_draw_from_a_mixed_pool() -> void:
	var draws := {}
	for s in 20:
		draws[str(_enemy_ids(4, s))] = true
	assert_int(draws.size()).is_greater(1)


func test_rewards_come_from_the_level() -> void:
	assert_dict(_table.rewards(2)).is_equal({"energy": int(_table.levels[2].rewards.energy), "material": int(_table.levels[2].rewards.material)})
