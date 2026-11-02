class_name EnemyArchetypeTable
extends RefCounted
## Every enemy archetype (EnemyArchetype), loaded from
## data/combat/archetypes.json.
## TODO(decision: tuning-format): the plan asks for .tres Resources; this repo
## keeps tuning as JSON in data/ read by a typed loader (combat-rework-map C1).

const DEFAULT_PATH := "res://data/combat/archetypes.json"

## Archetype id -> definition.
var archetypes: Dictionary[String, EnemyArchetype] = {}


## The shipped file; read from disk once, a fresh object every call.
static func load_default() -> EnemyArchetypeTable:
	var d: Variant = JsonFile.read_object_cached(DEFAULT_PATH)
	return from_dict(d) if d != null else load_file(DEFAULT_PATH)


static func load_file(path: String) -> EnemyArchetypeTable:
	var d: Variant = JsonFile.read_object(path)
	if d == null:
		push_error("EnemyArchetypeTable: cannot read %s" % path)
		return null
	return from_dict(d)


## Built from data shaped like archetypes.json: {"archetypes": {id: {...}}}.
## Keys starting with "_" are comments.
static func from_dict(d: Dictionary) -> EnemyArchetypeTable:
	var t := EnemyArchetypeTable.new()
	var entries: Dictionary = d.get("archetypes", {})
	for id: String in entries:
		if not id.begins_with("_"):
			t.archetypes[id] = EnemyArchetype.from_dict(id, entries[id])
	return t


func has(id: String) -> bool:
	return archetypes.has(id)


## Archetype `id`, or null when it is not defined.
func get_archetype(id: String) -> EnemyArchetype:
	return archetypes.get(id)


## Problems in the table; empty when every archetype is usable. Intent
## patterns are checked against `tuning`'s actions (the shipped ones when null).
func validate(tuning: CombatTuning = null) -> Array[String]:
	var t := tuning if tuning != null else CombatTuning.load_default()
	var action_ids := t.skills.keys()
	var problems: Array[String] = []
	for id in archetypes:
		problems.append_array(archetypes[id].validate(action_ids))
	return problems
