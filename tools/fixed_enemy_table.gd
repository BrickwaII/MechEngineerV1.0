class_name FixedEnemyTable
extends EnemyTable
## An enemy table that fields the same enemies every fight, in a set order,
## whatever the seed. Levels and rewards come from the table it copies, so the
## defense level still sets rewards and grid cost.

## Enemy ids fielded each fight, in roster order.
var fixed_ids: Array[String] = []


## A copy of `base` that fields `ids`. `extra_enemies` adds enemy definitions
## (id -> {name, hp, attack, ...}, shaped like enemy_tables.json) to the copy.
static func from_table(base: EnemyTable, ids: Array[String], extra_enemies: Dictionary = {}) -> FixedEnemyTable:
	var t := FixedEnemyTable.new()
	t.enemies = base.enemies.duplicate(true)
	t.enemies.merge(extra_enemies, true)
	t.levels = base.levels.duplicate(true)
	t.fixed_ids = ids.duplicate()
	return t


func pick(_level: int, _rng: RandomNumberGenerator) -> Array[String]:
	return fixed_ids.duplicate()
