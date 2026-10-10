class_name RunState
extends RefCounted
## Everything about a run in progress that a save must keep. Plain data; the
## rules that change it live in Campaign.

const FORMAT_VERSION := 1

## Id of the region file this run is played on.
var region_set_id: String
## Held region ids, in the region file's order.
var owned: PackedStringArray = []
## Pressure per held region id.
var pressure: Dictionary[String, float] = {}
var energy: float
var material: float
## Time points spent since the run began.
var time_points: int
## Grid capacity, in percent.
var grid: float


func duplicate_state() -> RunState:
	return from_dict(to_dict())


func to_dict() -> Dictionary:
	var held_pressure := {}
	for region_id in owned:
		held_pressure[region_id] = pressure.get(region_id, 0.0)
	return {
		"version": FORMAT_VERSION,
		"region_set_id": region_set_id,
		"owned": Array(owned),
		"pressure": held_pressure,
		"energy": energy,
		"material": material,
		"time_points": time_points,
		"grid": grid,
	}


## Builds a state from to_dict() output. Returns null if a field is missing or
## has the wrong type.
static func from_dict(d: Dictionary) -> RunState:
	if int(d.get("version", -1)) != FORMAT_VERSION:
		return null
	for key in ["region_set_id", "owned", "pressure", "energy", "material", "time_points", "grid"]:
		if not d.has(key):
			return null
	if not d["owned"] is Array or not d["pressure"] is Dictionary:
		return null
	var state := RunState.new()
	state.region_set_id = str(d["region_set_id"])
	for region_id: Variant in d["owned"]:
		state.owned.append(str(region_id))
	for region_id: Variant in d["pressure"]:
		state.pressure[str(region_id)] = float(d["pressure"][region_id])
	state.energy = float(d["energy"])
	state.material = float(d["material"])
	state.time_points = int(d["time_points"])
	state.grid = float(d["grid"])
	return state


## Writes the state in Godot's binary Variant format. Not JSON: Godot's JSON
## parser rounds some doubles on the way back in, and a reload must be exact.
func save_file(path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_var(to_dict())
	file.close()
	return OK


## Reads a state written by save_file(), or returns null.
static func load_file(path: String) -> RunState:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var data: Variant = file.get_var()
	return from_dict(data) if data is Dictionary else null
