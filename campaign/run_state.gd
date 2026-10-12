class_name RunState
extends RefCounted
## Everything about a run in progress that a save must keep. Plain data; the
## rules that change it live in Campaign.

const FORMAT_VERSION := 2

## Id of the region file this run is played on.
var region_set_id: String
## Index of the act being played, 0 for act 1.
var act: int
## Id of the starting location the run began from, or "" for the region file's
## default start.
var start_id: String
## Held region ids, in the region file's order.
var owned: PackedStringArray = []
## Pressure per held region id.
var pressure: Dictionary[String, float] = {}
var energy: float
var material: float
## Time points spent in this act.
var time_points: int
## Grid capacity, in percent.
var grid: float
## Per-day income the starting location adds for the whole run, keyed like
## MapRegion.provides.
var income_bonus: Dictionary[String, int] = {}
## Factor on the pressure rate of particular regions, from the starting
## location. Regions not listed build pressure at the normal rate.
var pressure_rate_factor: Dictionary[String, float] = {}
## The switchboard's next-run choices this run began with (decision id ->
## option id), so a saved run plays on with them. See CampaignVariants.
var variants: Dictionary[String, String] = {}
## auto-expansion progress per hostile region id, 0 to 100 percent.
var expansion: Dictionary[String, float] = {}
## The region the player last attacked or selected, or "".
var focus_id: String = ""
## Escalation's alert tier, fortification and days left alone; see Escalation.
var escalation: Dictionary = {}


func duplicate_state() -> RunState:
	return from_dict(to_dict())


func to_dict() -> Dictionary:
	var held_pressure := {}
	for region_id in owned:
		held_pressure[region_id] = pressure.get(region_id, 0.0)
	return {
		"version": FORMAT_VERSION,
		"region_set_id": region_set_id,
		"act": act,
		"start_id": start_id,
		"owned": Array(owned),
		"pressure": held_pressure,
		"energy": energy,
		"material": material,
		"time_points": time_points,
		"grid": grid,
		"income_bonus": Dictionary(income_bonus),
		"pressure_rate_factor": Dictionary(pressure_rate_factor),
		"variants": Dictionary(variants),
		"expansion": Dictionary(expansion),
		"focus_id": focus_id,
		"escalation": escalation.duplicate(true),
	}


## Builds a state from to_dict() output. Returns null if a field is missing or
## has the wrong type. A version 1 save, from before acts and starts, loads as
## act 1 with the default start. variants, expansion, focus_id and escalation
## are optional: a save from before them plays every default with no
## expansion progress, and Escalation works out its tier when it loads.
static func from_dict(d: Dictionary) -> RunState:
	var version := int(d.get("version", -1))
	if version != FORMAT_VERSION and version != 1:
		return null
	for key in ["region_set_id", "owned", "pressure", "energy", "material", "time_points", "grid"]:
		if not d.has(key):
			return null
	if version == FORMAT_VERSION:
		for key in ["act", "start_id", "income_bonus", "pressure_rate_factor"]:
			if not d.has(key):
				return null
		if not d["income_bonus"] is Dictionary or not d["pressure_rate_factor"] is Dictionary:
			return null
	if not d["owned"] is Array or not d["pressure"] is Dictionary:
		return null
	var state := RunState.new()
	state.region_set_id = str(d["region_set_id"])
	state.act = int(d.get("act", 0))
	state.start_id = str(d.get("start_id", ""))
	for region_id: Variant in d["owned"]:
		state.owned.append(str(region_id))
	for region_id: Variant in d["pressure"]:
		state.pressure[str(region_id)] = float(d["pressure"][region_id])
	state.energy = float(d["energy"])
	state.material = float(d["material"])
	state.time_points = int(d["time_points"])
	state.grid = float(d["grid"])
	var bonus: Dictionary = d.get("income_bonus", {})
	for key: Variant in bonus:
		state.income_bonus[str(key)] = int(bonus[key])
	var factors: Dictionary = d.get("pressure_rate_factor", {})
	for region_id: Variant in factors:
		state.pressure_rate_factor[str(region_id)] = float(factors[region_id])
	var chosen: Variant = d.get("variants", {})
	var progress: Variant = d.get("expansion", {})
	if not chosen is Dictionary or not progress is Dictionary:
		return null
	for decision: Variant in chosen:
		state.variants[str(decision)] = str(chosen[decision])
	for region_id: Variant in progress:
		state.expansion[str(region_id)] = float(progress[region_id])
	state.focus_id = str(d.get("focus_id", ""))
	var escalation: Variant = d.get("escalation", {})
	if not escalation is Dictionary:
		return null
	state.escalation = (escalation as Dictionary).duplicate(true)
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
