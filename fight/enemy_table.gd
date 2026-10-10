class_name EnemyTable
extends RefCounted
## Enemy definitions and which ones each defense level fields, loaded from
## data/combat/enemy_tables.json.

const DEFAULT_PATH := "res://data/combat/enemy_tables.json"

## Enemy id -> {name, hp, attack, defense, speed, elasticity, battery_capacity, skills}.
var enemies: Dictionary = {}
## Defense level -> {count, pool, rewards}.
var levels: Dictionary = {}
## Which faction fields enemies where (data/combat/factions.json). Null: every
## fight draws from the generic level pools.
var factions: FactionTable


## The shipped table, with the shipped factions.


static func load_default() -> EnemyTable:
	var t := load_file(DEFAULT_PATH)
	if t != null:
		t.factions = FactionTable.load_default()
	return t


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


## Enemy ids for `request`'s fight: the faction holding its territory under
## `faction_rule` (a FightVariants enemy-factions option), or the generic
## pool of its level when no faction holds it.
func pick_for(request: FightRequest, rng: RandomNumberGenerator,
		faction_rule := FightVariants.FACTIONS_BY_ACT) -> Array[String]:
	if factions != null:
		var ids := factions.pick_for_territory(self, request.territory_id, request.defense_level, faction_rule, rng)
		if not ids.is_empty():
			return ids
	return pick(request.defense_level, rng)


## The sprite that draws `enemy_id`: {"unit": manifest unit id, "tier": tier},
## or {} when the enemy names none.
func sprite_of(enemy_id: String) -> Dictionary:
	var e: Dictionary = enemies.get(enemy_id, {})
	if not e.has("sprite"):
		return {}
	return {"unit": str(e.sprite), "tier": str(e.get("tier", "beginner"))}


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
	if factions != null:
		problems.append_array(factions.validate(self))
	return problems
