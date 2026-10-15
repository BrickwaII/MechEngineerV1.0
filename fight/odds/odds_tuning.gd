class_name OddsTuning
extends RefCounted
## The numbers behind the simulated odds, from data/combat/odds.json: how many
## auto-fights an estimate plays, and the win-rate bands that name the odds.

const DEFAULT_PATH := "res://data/combat/odds.json"

## Auto-fights per estimate.
var runs := 0
## Best first: [{"min_win_percent": float, "label": String}].
var bands: Array[Dictionary] = []
var errors: Array[String] = []

static var _cached_default: OddsTuning


## The shipped tuning. Read once and shared; do not change it.
static func load_default() -> OddsTuning:
	if _cached_default == null:
		_cached_default = load_file(DEFAULT_PATH)
	return _cached_default


static func load_file(path: String) -> OddsTuning:
	var d: Variant = JsonFile.read_object(path)
	if d == null:
		var t := OddsTuning.new()
		t.errors.append("cannot read %s" % path)
		return t
	return from_dict(d)


static func from_dict(d: Dictionary) -> OddsTuning:
	var t := OddsTuning.new()
	t.runs = int(d.get("runs", 0))
	if t.runs < 1:
		t.errors.append("runs must be at least 1")
	var last := INF
	for band: Variant in d.get("bands", []):
		if not band is Dictionary or not band.has("min_win_percent") or not band.has("label"):
			t.errors.append("bands entries need min_win_percent and label")
			continue
		var min_percent := float(band["min_win_percent"])
		if min_percent >= last:
			t.errors.append("bands must be listed best first")
		last = min_percent
		t.bands.append({"min_win_percent": min_percent, "label": str(band["label"])})
	if t.bands.is_empty():
		t.errors.append("bands is empty")
	return t


## The label for a win rate in percent: the first band it reaches, else the last.
func label_for(win_percent: float) -> String:
	for band in bands:
		if win_percent >= band["min_win_percent"]:
			return band["label"]
	return bands[-1]["label"] if not bands.is_empty() else ""


## The position of `label` in the bands, best first; -1 when unknown.
func band_index(label: String) -> int:
	for i in bands.size():
		if bands[i]["label"] == label:
			return i
	return -1
