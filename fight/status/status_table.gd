class_name StatusTable
extends RefCounted
## Every status definition (StatusDef), loaded from data/combat/statuses.json.
## TODO(decision: tuning-format): the plan asks for .tres Resources; this repo
## keeps tuning as JSON in data/ read by a typed loader (combat-rework-map C1).

const DEFAULT_PATH := "res://data/combat/statuses.json"

## Status id -> definition.
var statuses: Dictionary[String, StatusDef] = {}


## The shipped file; read from disk once, a fresh object every call.
static func load_default() -> StatusTable:
	var d: Variant = JsonFile.read_object_cached(DEFAULT_PATH)
	return from_dict(d) if d != null else load_file(DEFAULT_PATH)


static func load_file(path: String) -> StatusTable:
	var d: Variant = JsonFile.read_object(path)
	if d == null:
		push_error("StatusTable: cannot read %s" % path)
		return null
	return from_dict(d)


## Built from data shaped like statuses.json: {"statuses": {id: {...}}}.
## Keys starting with "_" are comments.
static func from_dict(d: Dictionary) -> StatusTable:
	var t := StatusTable.new()
	var entries: Dictionary = d.get("statuses", {})
	for id: String in entries:
		if not id.begins_with("_"):
			t.statuses[id] = StatusDef.from_dict(id, entries[id])
	return t


func has(id: String) -> bool:
	return statuses.has(id)


## Status `id`, or null when it is not defined.
func get_status(id: String) -> StatusDef:
	return statuses.get(id)


func ids() -> Array[String]:
	var out: Array[String] = []
	out.assign(statuses.keys())
	return out


## Problems in the table; empty when every status is usable.
func validate() -> Array[String]:
	var problems: Array[String] = []
	for id in statuses:
		problems.append_array(statuses[id].validate())
	return problems
