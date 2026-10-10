class_name EnemyTable
extends RefCounted
## Enemy definitions and which ones each defense level fields, loaded from
## data/combat/enemy_tables.json.

const DEFAULT_PATH := "res://data/combat/enemy_tables.json"

## Enemy id -> {name, hp, attack, defense, speed, elasticity, battery_capacity, skills}.
var enemies: Dictionary = {}
## Defense level -> {count, pool, rewards}.
var levels: Dictionary = {}


static func load_default() -> EnemyTable:
	return load_file(DEFAULT_PATH)


static func load_file(path: String) -> EnemyTable:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("EnemyTable: cannot read %s" % path)
		return null
	return from_dict(parsed)


static func from_dict(d: Dictionary) -> EnemyTable:
	var t := EnemyTable.new()
	t.enemies = d.enemies
	for entry: Dictionary in d.levels:
		t.levels[int(entry.level)] = entry
	return t


func has_level(level: int) -> bool:
	return levels.has(level)


func stats_of(enemy_id: String) -> UnitStats:
	var e: Dictionary = enemies[enemy_id]
	return UnitStats.new(
		int(e.hp), int(e.attack), int(e.defense), int(e.speed), int(e.elasticity), int(e.battery_capacity))


func name_of(enemy_id: String) -> String:
	return enemies[enemy_id].name


func skills_of(enemy_id: String) -> Array[String]:
	var out: Array[String] = []
	for s: String in enemies[enemy_id].skills:
		out.append(s)
	return out


## Enemy ids for one fight at `level`, drawn from the level's pool with `rng`.
func pick(level: int, rng: RandomNumberGenerator) -> Array[String]:
	var entry: Dictionary = levels[level]
	var pool: Array = entry.pool
	var out: Array[String] = []
	for i in int(entry.count):
		out.append(pool[rng.randi_range(0, pool.size() - 1)])
	return out


func rewards(level: int) -> Dictionary[String, int]:
	var out: Dictionary[String, int] = {}
	var r: Dictionary = levels[level].rewards
	for key: String in r:
		out[key] = int(r[key])
	return out


## Problems in the table; empty when every level and enemy is usable.
func validate(tuning: CombatTuning) -> Array[String]:
	var problems: Array[String] = []
	for level in range(FightRequest.MIN_DEFENSE_LEVEL, FightRequest.MAX_DEFENSE_LEVEL + 1):
		if not levels.has(level):
			problems.append("no entry for defense level %d" % level)
			continue
		if int(levels[level].count) < 1:
			problems.append("level %d fields no enemies" % level)
		for id: String in levels[level].pool:
			if not enemies.has(id):
				problems.append("level %d names unknown enemy %s" % [level, id])
	for id: String in enemies:
		for s: String in enemies[id].skills:
			if tuning.skill(s) == null:
				problems.append("enemy %s has unknown skill %s" % [id, s])
	return problems
