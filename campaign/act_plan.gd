class_name ActPlan
extends RefCounted
## The acts of a run and the zoom between them, read from data/tuning/acts.json.
## Each act is a region file and a tuning file. When an act's payload arrives,
## the run zooms out to the next act's larger map: the region the last map sat
## in (the next act's zoom_focus) is held, plus a neighbor or two for holding
## much of the last map, and resources, grid and the starting location's
## income bonus carry over. Nothing here has a default: a missing key is an
## error, so the file stays the one source.
##
## Each act offers map variants, region files of the same place cut into more
## or fewer regions; the act plays its "default_variant" unless another is
## chosen with choose_variant() (the dev menu does). A variant's id is the id
## of its region file, so a save's region_set_id names the variant it was on.
##
## The shipped acts: the cities around Lake Washington, North America by state,
## province or group of them (the lake sits in Washington), then the world on
## a globe (North America sits in the United States). Each act's tuning file
## sets its pacing: countdown, action time costs and pressure.
## TODO(decision: act-pacing): every act has the same countdown and costs for
## now, and pressure scales with region count; see data/tuning/act*.json. The
## switchboard's act-pacing presets override them per act (ActPacing, applied
## by Campaign).
## TODO(decision: map-variants): the defaults (Lake Washington 12, North
## America 33, the world 20) are a first pick; the user is trying the others.
## TODO(decision: zoom-carryover): what carries across the zoom (all stock, a
## grid top-up, bonus regions for ground held, the start's income bonus) is a
## placeholder rule set; the numbers are in acts.json.

## [{id, name, tuning_file, variants, default_variant}, plus the chosen
## variant's variant, region_file and zoom_focus]. variants is
## [{id, name, region_file, zoom_focus}]; zoom_focus is "" in the first act.
var acts: Array[Dictionary] = []

# What carries across a zoom.
## Fraction of energy and material stock kept.
var energy_kept: float
var material_kept: float
## Grid percent restored on arrival, up to the next act's max_grid.
var grid_restore: float
## One extra held region in the next act per this many regions held at the
## payload, up to max_bonus_regions.
var held_per_bonus_region: int
var max_bonus_regions: int
## Whether the starting location's income bonus carries into the next act.
var keep_income_bonus: bool

# The zoom transition on screen, in seconds.
var fade_seconds: float
var zoom_seconds: float

var errors: Array[String] = []


static func load_file(path: String) -> ActPlan:
	var plan := ActPlan.new()
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		plan.errors.append("cannot read %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return plan
	var data: Variant = JSON.parse_string(text)
	if not data is Dictionary:
		plan.errors.append("%s is not a JSON object" % path)
		return plan
	plan._read(data)
	return plan


static func from_dict(data: Dictionary) -> ActPlan:
	var plan := ActPlan.new()
	plan._read(data)
	return plan


func is_valid() -> bool:
	return errors.is_empty()


func act_count() -> int:
	return acts.size()


func has_next(act: int) -> bool:
	return act + 1 < acts.size()


func act_name(act: int) -> String:
	return acts[act]["name"] if act >= 0 and act < acts.size() else ""


## The variants an act offers, in file order: [{id, name, region_file, zoom_focus}].
func variants(act: int) -> Array:
	return acts[act]["variants"] if act >= 0 and act < acts.size() else []


## The id of the variant an act plays.
func chosen_variant(act: int) -> String:
	return acts[act]["variant"]


## Plays the variant with this id in this act from now on. False, and nothing
## changes, if the act has no such variant. "" picks the act's default.
func choose_variant(act: int, variant_id: String) -> bool:
	if act < 0 or act >= acts.size():
		return false
	var wanted := variant_id if not variant_id.is_empty() else str(acts[act]["default_variant"])
	for variant: Dictionary in acts[act]["variants"]:
		if variant["id"] == wanted:
			acts[act]["variant"] = variant["id"]
			acts[act]["region_file"] = variant["region_file"]
			acts[act]["zoom_focus"] = variant["zoom_focus"]
			return true
	return false


func load_map(act: int) -> RegionMap:
	return RegionMap.load_file(acts[act]["region_file"])


func load_tuning(act: int) -> MapTuning:
	return MapTuning.load_file(acts[act]["tuning_file"])


## How many extra regions a run that held `held` regions at the payload gets in
## the next act.
func bonus_region_count(held: int) -> int:
	return mini(max_bonus_regions, held / held_per_bonus_region)


## The regions the next act starts with: its zoom_focus, then the focus's
## lowest-defense neighbors (file order on a tie), one per bonus earned.
## Falls back to the map's starts_owned regions if the focus is missing.
func zoom_regions(next_act: int, next_map: RegionMap, held: int) -> PackedStringArray:
	var focus_id: String = acts[next_act]["zoom_focus"]
	var focus := next_map.get_region(focus_id)
	if focus == null:
		push_error("ActPlan: act %d zoom_focus '%s' is not on map '%s'" % [next_act, focus_id, next_map.id])
		return next_map.starting_ids()
	var neighbors: Array[MapRegion] = []
	for region in next_map.regions:
		if focus.is_adjacent_to(region.id):
			neighbors.append(region)
	# sort_custom is not stable; compare file order on a tie.
	var order := next_map.ids()
	neighbors.sort_custom(func(a: MapRegion, b: MapRegion) -> bool:
		return a.defense < b.defense if a.defense != b.defense else order.find(a.id) < order.find(b.id))
	var picked := PackedStringArray([focus_id])
	for i in mini(bonus_region_count(held), neighbors.size()):
		picked.append(neighbors[i].id)
	var out := PackedStringArray()
	for region_id in order:
		if region_id in picked:
			out.append(region_id)
	return out


## The state the next act starts from, given the state at the end of this one.
func zoom_state(from: RunState, next_map: RegionMap, next_tuning: MapTuning) -> RunState:
	var s := RunState.new()
	s.act = from.act + 1
	s.region_set_id = next_map.id
	s.start_id = from.start_id
	s.owned = zoom_regions(s.act, next_map, from.owned.size())
	for region_id in s.owned:
		s.pressure[region_id] = next_tuning.start_pressure
	s.energy = from.energy * energy_kept
	s.material = from.material * material_kept
	s.grid = minf(next_tuning.max_grid, from.grid + grid_restore)
	s.time_points = 0
	for key in MapRegion.RESOURCE_KEYS:
		s.income_bonus[key] = from.income_bonus.get(key, 0) if keep_income_bonus else 0
	# The run's variant choices hold for every act; expansion starts afresh.
	s.variants = from.variants.duplicate()
	return s


func _read(d: Dictionary) -> void:
	var list: Variant = d.get("acts")
	if not list is Array or (list as Array).is_empty():
		errors.append("acts needs a non-empty 'acts' list")
	else:
		for i in (list as Array).size():
			var entry: Variant = list[i]
			if not entry is Dictionary:
				errors.append("act %d is not an object" % (i + 1))
				continue
			var act := {}
			for key in ["id", "name", "tuning_file", "default_variant"]:
				var v: Variant = entry.get(key)
				if not v is String or (v as String).is_empty():
					errors.append("act %d needs a non-empty '%s'" % [i + 1, key])
				act[key] = str(v)
			act["variants"] = _read_variants(entry.get("variants"), i)
			acts.append(act)
			if not choose_variant(i, ""):
				errors.append("act %d's default_variant '%s' is not one of its variants" % [i + 1, act["default_variant"]])
				act["variant"] = ""
				act["region_file"] = ""
				act["zoom_focus"] = ""
	energy_kept = _num(d, "zoom.energy_kept")
	material_kept = _num(d, "zoom.material_kept")
	grid_restore = _num(d, "zoom.grid_restore")
	held_per_bonus_region = int(_num(d, "zoom.held_per_bonus_region"))
	max_bonus_regions = int(_num(d, "zoom.max_bonus_regions"))
	var keep: Variant = _lookup(d, "zoom.keep_income_bonus")
	if keep != null and not keep is bool:
		errors.append("acts 'zoom.keep_income_bonus' must be true or false")
	keep_income_bonus = keep == true
	fade_seconds = _num(d, "zoom.fade_seconds")
	zoom_seconds = _num(d, "zoom.zoom_seconds")
	if held_per_bonus_region <= 0:
		errors.append("acts 'zoom.held_per_bonus_region' must be above 0")


func _read_variants(list: Variant, i: int) -> Array:
	var out := []
	if not list is Array or (list as Array).is_empty():
		errors.append("act %d needs a non-empty 'variants' list" % (i + 1))
		return out
	for entry: Variant in list:
		if not entry is Dictionary:
			errors.append("act %d has a variant that is not an object" % (i + 1))
			continue
		var variant := {}
		for key in ["id", "name", "region_file"]:
			var v: Variant = entry.get(key)
			if not v is String or (v as String).is_empty():
				errors.append("act %d variant needs a non-empty '%s'" % [i + 1, key])
			variant[key] = str(v)
		var focus: Variant = entry.get("zoom_focus", "")
		if i > 0 and (not focus is String or (focus as String).is_empty()):
			errors.append("act %d variant '%s' needs a 'zoom_focus' region id" % [i + 1, variant["id"]])
		variant["zoom_focus"] = str(focus)
		out.append(variant)
	return out


func _lookup(d: Dictionary, path: String) -> Variant:
	var v: Variant = d
	for key in path.split("."):
		if not v is Dictionary or not (v as Dictionary).has(key):
			errors.append("acts is missing '%s'" % path)
			return null
		v = v[key]
	return v


func _num(d: Dictionary, path: String) -> float:
	var v: Variant = _lookup(d, path)
	if v == null:
		return 0.0
	if not (v is float or v is int):
		errors.append("acts '%s' must be a number" % path)
		return 0.0
	return float(v)
