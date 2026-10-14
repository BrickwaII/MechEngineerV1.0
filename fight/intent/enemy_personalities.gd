class_name EnemyPersonalities
extends RefCounted
## A Personality per enemy id, loaded from
## data/combat/intent/enemy_personalities.json. An enemy with no entry is
## balanced. Tests and callers may also pin a personality to one unit id.
## TODO(decision: d-personality-map): the values are first guesses.

const DEFAULT_PATH := "res://data/combat/intent/enemy_personalities.json"

## Enemy id (as in enemy_tables.json) -> Personality.
var by_enemy: Dictionary[String, Personality] = {}
## Combatant id -> Personality. Wins over by_enemy.
var by_unit: Dictionary[String, Personality] = {}


## The shipped file; read from disk once, a fresh object every call.
static func load_default() -> EnemyPersonalities:
	var d: Variant = JsonFile.read_object_cached(DEFAULT_PATH)
	return from_dict(d) if d != null else load_file(DEFAULT_PATH)


static func load_file(path: String) -> EnemyPersonalities:
	var d: Variant = JsonFile.read_object(path)
	if d == null:
		push_error("EnemyPersonalities: cannot read %s" % path)
		return null
	return from_dict(d)


static func from_dict(d: Dictionary) -> EnemyPersonalities:
	var p := EnemyPersonalities.new()
	var enemies: Dictionary = d.get("enemies", {})
	for id: String in enemies:
		var e: Dictionary = enemies[id]
		p.by_enemy[id] = Personality.new(
			int(e.get("generation", Personality.SCALE_COUNT)),
			float(e.get("aggressive_defensive", 0.0)),
			float(e.get("solitary_supportive", 0.0)),
			float(e.get("reactive_methodical", 0.0)))
	return p


## The enemy id a combatant was built from: "rust_hound#2" -> "rust_hound".
static func enemy_id_of(unit_id: String) -> String:
	return unit_id.get_slice("#", 0)


## The personality of a combatant. Never null.
func for_unit(unit_id: String) -> Personality:
	if by_unit.has(unit_id):
		return by_unit[unit_id]
	return by_enemy.get(enemy_id_of(unit_id), Personality.new(Personality.SCALE_COUNT))


## Enemy ids in `table` that have no personality entry.
func missing_from(table: EnemyTable) -> Array[String]:
	var out: Array[String] = []
	for id: String in table.enemies:
		if not by_enemy.has(id):
			out.append(id)
	return out
