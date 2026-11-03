class_name BattleDebugSettings
extends RefCounted
## Settings for the battle debug simulator (S9b), read from
## data/dev/battle_debugger.json.

const DEFAULT_PATH := "res://data/dev/battle_debugger.json"

var simulate_runs := 100
var simulate_policies: Array[String] = []
## False: every simulated fight fields the live fight's enemies, as edited.
## True: enemies are drawn per seed from the enemy table.
## TODO(decision: debugger-sim-enemies)
var draw_enemies := false
## Data file key (BattleDebugSession.FILE_*) -> path Save to data writes.
var data_files: Dictionary = {}
var export_dir := ""
var max_snapshots := 2000
var panel_width := 420
var log_lines_shown := 12
var timeline_shown := 10
var toggle_key := "F6"


static func load_default() -> BattleDebugSettings:
	var d: Variant = JsonFile.read_object_cached(DEFAULT_PATH)
	return from_dict(d if d != null else {})


static func from_dict(d: Dictionary) -> BattleDebugSettings:
	var s := BattleDebugSettings.new()
	s.simulate_runs = int(d.get("simulate_runs", 100))
	for p: Variant in d.get("simulate_policies", ["greedy", "smart"]):
		s.simulate_policies.append(String(p))
	s.draw_enemies = bool(d.get("draw_enemies", false))
	var files: Dictionary = d.get("data_files", {})
	for key: String in files:
		s.data_files[key] = String(files[key])
	s.export_dir = String(d.get("export_dir", "user://dev/tuning_diffs"))
	s.max_snapshots = int(d.get("max_snapshots", 2000))
	s.panel_width = int(d.get("panel_width", 420))
	s.log_lines_shown = int(d.get("log_lines_shown", 12))
	s.timeline_shown = int(d.get("timeline_shown", 10))
	s.toggle_key = String(d.get("toggle_key", "F6"))
	return s


func validate() -> Array[String]:
	var problems: Array[String] = []
	if simulate_runs < 1:
		problems.append("simulate_runs must be at least 1")
	if simulate_policies.is_empty():
		problems.append("simulate_policies is empty")
	if max_snapshots < 1:
		problems.append("max_snapshots must be at least 1")
	if OS.find_keycode_from_string(toggle_key) == KEY_NONE:
		problems.append("toggle_key %s is not a key" % toggle_key)
	return problems
