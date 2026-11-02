class_name ActionTable
extends RefCounted
## Every action definition (the plan's ActionDef, here CombatSkill), loaded
## from data/combat/actions.json. CombatTuning reads its skills from here.
## TODO(decision: tuning-format): the plan asks for .tres Resources; this repo
## keeps tuning as JSON in data/ read by a typed loader (combat-rework-map C1).

const DEFAULT_PATH := "res://data/combat/actions.json"

## Action id -> definition, in file order.
var actions: Dictionary[String, CombatSkill] = {}


## The shipped file; read from disk once, fresh objects every call.
static func load_default() -> ActionTable:
	var d: Variant = JsonFile.read_object_cached(DEFAULT_PATH)
	return from_dict(d) if d != null else load_file(DEFAULT_PATH)


static func load_file(path: String) -> ActionTable:
	var d: Variant = JsonFile.read_object(path)
	if d == null:
		push_error("ActionTable: cannot read %s" % path)
		return null
	return from_dict(d)


## Built from data shaped like actions.json: {"actions": {id: {...}}}.
## Keys starting with "_" are comments.
static func from_dict(d: Dictionary) -> ActionTable:
	var t := ActionTable.new()
	var entries: Dictionary = d.get("actions", {})
	for id: String in entries:
		if not id.begins_with("_"):
			t.actions[id] = CombatSkill.from_dict(id, entries[id])
	return t


## Problems in the table; empty when every action is usable. Status names are
## checked against `statuses` (the shipped table when null).
func validate(statuses: StatusTable = null) -> Array[String]:
	var table := statuses if statuses != null else StatusTable.load_default()
	var problems: Array[String] = []
	if actions.is_empty():
		problems.append("no actions")
	for id in actions:
		problems.append_array(actions[id].validate(table.ids()))
	return problems
