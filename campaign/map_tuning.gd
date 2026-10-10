class_name MapTuning
extends RefCounted
## Every overworld number, read from a tuning file in data/tuning/. Nothing here
## has a default: a missing key is an error, so the file stays the one source.
##
## A file may name a "base" file (a res:// path) and give only what differs:
## its keys are laid over the base's, nested objects key by key. Each act's
## file in data/tuning/ extends overworld.json that way.

## How nodes are drawn: FULL shows the pressure ring or defense pips, the name,
## resource chips and the cause line on every region; COMPACT shows a small
## ring or pips and the short name, with the full node on the selected region
## only. For maps too crowded for full nodes.
const NODE_FULL := "full"
const NODE_COMPACT := "compact"

# Time, in points. A day is points_per_day points.
var points_per_day: int
var total_points: int
var attack_time: int
var reinforce_time: int
var wait_time: int
## How many points the time bar shows, and how many of those lie in the past.
var bar_window_points: int
var bar_history_points: int

# Pressure, 0 to forces_defense_at, per held region.
var pressure_rate_base: float
var pressure_rate_per_base: float
var border_multiplier: float
var start_pressure: float
var forces_defense_at: float
var reinforce_relief: float
var pressure_after_capture: float
var pressure_after_defense_victory: float
## Factor on every pressure rate in this act.
var pressure_scale: float
## When above 0, pressure rates are also scaled by this over the map's region
## count, so a map with more regions builds pressure more slowly on each and
## a run holds about as much pressure in total whichever map variant it is on.
## TODO(decision: act-pacing): with 0 the map size changes nothing.
var pressure_reference_regions: int
## Defense level of a forced fight with no hostile neighbor to blame.
var uprising_defense_level: int
## Pressure at which a held node's cause line turns to a warning, and at
## which the warning turns urgent; ring_warning_at colors the ring.
var cause_warning_at: float
var imminent_at: float
var ring_warning_at: float
## [{below: float, word: String}], lowest first: how fast pressure is rising,
## in words, for a rate per point below `below`.
var rate_words: Array[Dictionary] = []

# Grid capacity, in percent of a full grid.
var start_grid: float
var max_grid: float
var grid_regen_divisor: float
var attack_grid_base: float
var attack_grid_per_defense: float
var defeat_grid_multiplier: float
var reinforce_grid_cost: float

var start_energy: float
var start_material: float

## Squad attack plus defense points worth one level when judging odds.
var squad_stat_points_per_level: int
## [{min_margin: int, label: String}], highest margin first.
var odds_bands: Array[Dictionary] = []
## Index = defense level. [{label: String, opposition: String}].
var defense_levels: Array[Dictionary] = []

var event_log_length: int

## The stub boss fight at the last act's payload: its defense level.
## TODO(decision: boss-fight): a stand-in until the boss fight is designed.
var boss_defense_level: int

# The map view.
## NODE_FULL or NODE_COMPACT.
var node_style: String
## On a globe: the globe's diameter as a fraction of the view's shorter side,
## degrees turned per pixel dragged, the furthest the poles tilt toward the
## viewer, how far the mouse may move before a press counts as a drag, the
## longest outline edge before it is split so it curves with the globe, and
## how squarely a node must face the viewer to be drawn (0 at the rim, 1 at
## the middle).
var globe_size: float
var globe_degrees_per_pixel: float
var globe_max_tilt: float
var globe_drag_threshold: float
var globe_edge_degrees: float
var globe_node_min_facing: float

var errors: Array[String] = []
## The settings this tuning was read from, its base laid in, for
## with_overrides().
var source: Dictionary = {}


static func load_file(path: String) -> MapTuning:
	var tuning := MapTuning.new()
	var data := _read_file(path, tuning.errors, [])
	if tuning.errors.is_empty():
		tuning.source = data
		tuning._read(data)
	return tuning


## The file's settings laid over its base's, recursively. `seen` stops a
## file that names itself as its own base, directly or not.
static func _read_file(path: String, errors: Array[String], seen: Array) -> Dictionary:
	if path in seen:
		errors.append("tuning base loop at %s" % path)
		return {}
	seen.append(path)
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		errors.append("cannot read %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return {}
	var data: Variant = JSON.parse_string(text)
	if not data is Dictionary:
		errors.append("%s is not a JSON object" % path)
		return {}
	var d: Dictionary = data
	if not d.has("base"):
		return d
	if not d["base"] is String:
		errors.append("%s 'base' must be a res:// path" % path)
		return {}
	var merged := _read_file(d["base"], errors, seen)
	_lay_over(merged, d)
	merged.erase("base")
	return merged


static func _lay_over(base: Dictionary, over: Dictionary) -> void:
	for key: Variant in over:
		if over[key] is Dictionary and base.get(key) is Dictionary:
			_lay_over(base[key], over[key])
		else:
			base[key] = over[key]


static func from_dict(data: Dictionary) -> MapTuning:
	var tuning := MapTuning.new()
	tuning.source = data
	tuning._read(data)
	return tuning


## A copy with `over` laid over these settings, nested objects key by key, as
## a file lays over its base. Used by act pacing presets (ActPacing).
func with_overrides(over: Dictionary) -> MapTuning:
	var merged := source.duplicate(true)
	_lay_over(merged, over.duplicate(true))
	var tuning := from_dict(merged)
	tuning.errors.append_array(errors)
	return tuning


func is_valid() -> bool:
	return errors.is_empty()


func defense_label(level: int) -> String:
	return defense_levels[level]["label"] if level >= 0 and level < defense_levels.size() else ""


## How fast pressure rises at this rate per point, in a word such as "slowly".
func rate_word(rate: float) -> String:
	for entry in rate_words:
		if rate < entry["below"]:
			return entry["word"]
	return rate_words[-1]["word"] if not rate_words.is_empty() else ""


func opposition(level: int) -> String:
	return defense_levels[level]["opposition"] if level >= 0 and level < defense_levels.size() else ""


func _read(d: Dictionary) -> void:
	points_per_day = int(_num(d, "time.points_per_day"))
	total_points = int(_num(d, "time.total_points"))
	attack_time = int(_num(d, "time.action_cost.attack"))
	reinforce_time = int(_num(d, "time.action_cost.reinforce"))
	wait_time = int(_num(d, "time.action_cost.wait"))
	bar_window_points = int(_num(d, "time.bar_window_points"))
	bar_history_points = int(_num(d, "time.bar_history_points"))

	pressure_rate_base = _num(d, "pressure.rate_base")
	pressure_rate_per_base = _num(d, "pressure.rate_per_pressure_base")
	border_multiplier = _num(d, "pressure.border_multiplier")
	start_pressure = _num(d, "pressure.start")
	forces_defense_at = _num(d, "pressure.forces_defense_at")
	reinforce_relief = _num(d, "pressure.reinforce_relief")
	pressure_after_capture = _num(d, "pressure.after_capture")
	pressure_after_defense_victory = _num(d, "pressure.after_defense_victory")
	pressure_scale = _num(d, "pressure.scale")
	pressure_reference_regions = int(_num(d, "pressure.reference_regions"))
	uprising_defense_level = int(_num(d, "pressure.uprising_defense_level"))
	cause_warning_at = _num(d, "pressure.cause_warning_at")
	imminent_at = _num(d, "pressure.imminent_at")
	ring_warning_at = _num(d, "pressure.ring_warning_at")
	for entry: Variant in _list(d, "pressure.rate_words"):
		if entry is Dictionary and entry.get("below") is float and entry.get("word") is String:
			rate_words.append({"below": entry["below"], "word": entry["word"]})
		else:
			errors.append("pressure.rate_words entries need below and word")

	start_grid = _num(d, "grid.start")
	max_grid = _num(d, "grid.max")
	grid_regen_divisor = _num(d, "grid.regen_divisor")
	attack_grid_base = _num(d, "grid.attack_base_cost")
	attack_grid_per_defense = _num(d, "grid.attack_cost_per_defense")
	defeat_grid_multiplier = _num(d, "grid.defeat_multiplier")
	reinforce_grid_cost = _num(d, "grid.reinforce_cost")

	start_energy = _num(d, "resources.start_energy")
	start_material = _num(d, "resources.start_material")

	squad_stat_points_per_level = int(_num(d, "odds.squad_stat_points_per_level"))
	for band: Variant in _list(d, "odds.bands"):
		if band is Dictionary and band.get("min_margin") is float and band.get("label") is String:
			odds_bands.append({"min_margin": int(band["min_margin"]), "label": band["label"]})
		else:
			errors.append("odds.bands entries need min_margin and label")
	for level: Variant in _list(d, "defense_levels"):
		if level is Dictionary and level.get("label") is String and level.get("opposition") is String:
			defense_levels.append({"label": level["label"], "opposition": level["opposition"]})
		else:
			errors.append("defense_levels entries need label and opposition")
	if defense_levels.size() != MapRegion.MAX_DEFENSE + 1:
		errors.append("defense_levels needs one entry per level 0 to %d" % MapRegion.MAX_DEFENSE)

	event_log_length = int(_num(d, "event_log_length"))
	boss_defense_level = int(_num(d, "boss.defense_level"))
	if boss_defense_level < MapRegion.MIN_DEFENSE or boss_defense_level > MapRegion.MAX_DEFENSE:
		errors.append("boss.defense_level must be %d to %d" % [MapRegion.MIN_DEFENSE, MapRegion.MAX_DEFENSE])

	var style: Variant = _lookup(d, "view.node_style")
	if style != null and style != NODE_FULL and style != NODE_COMPACT:
		errors.append("view.node_style must be '%s' or '%s'" % [NODE_FULL, NODE_COMPACT])
	node_style = str(style)
	globe_size = _num(d, "view.globe.size")
	globe_degrees_per_pixel = _num(d, "view.globe.degrees_per_pixel")
	globe_max_tilt = _num(d, "view.globe.max_tilt")
	globe_drag_threshold = _num(d, "view.globe.drag_threshold_px")
	globe_edge_degrees = _num(d, "view.globe.edge_degrees")
	globe_node_min_facing = _num(d, "view.globe.node_min_facing")
	if globe_size <= 0.0 or globe_edge_degrees <= 0.0:
		errors.append("view.globe.size and view.globe.edge_degrees must be above 0")

	if points_per_day <= 0 or grid_regen_divisor <= 0.0 or squad_stat_points_per_level <= 0:
		errors.append("points_per_day, grid.regen_divisor and odds.squad_stat_points_per_level must be above 0")


func _lookup(d: Dictionary, path: String) -> Variant:
	var v: Variant = d
	for key in path.split("."):
		if not v is Dictionary or not (v as Dictionary).has(key):
			errors.append("tuning is missing '%s'" % path)
			return null
		v = v[key]
	return v


func _num(d: Dictionary, path: String) -> float:
	var v: Variant = _lookup(d, path)
	if v == null:
		return 0.0
	if not (v is float or v is int):
		errors.append("tuning '%s' must be a number" % path)
		return 0.0
	return float(v)


func _list(d: Dictionary, path: String) -> Array:
	var v: Variant = _lookup(d, path)
	if v == null:
		return []
	if not v is Array:
		errors.append("tuning '%s' must be a list" % path)
		return []
	return v
