extends SceneTree
## Command line batch simulator. Runs a scenario many times headless and prints
## win rate, fight length and energy spent.
##
##   godot --headless --path . -s res://tools/batch_sim.gd -- \
##       --scenario res://data/scenarios/level2_drafted_squad.json --runs 200
##
## Options (defaults in data/scenarios/_dev_tools.json):
##   --scenario PATH   scenario JSON file (required)
##   --runs N          number of fights
##   --seed N          seed of the first fight; fight i uses seed + i
##   --log PATH        stats log to append to; "none" to skip logging
##
## Policy comparison (the simulation harness, combat rework S8; defaults in
## data/scenarios/_harness.json):
##
##   godot --headless --path . -s res://tools/batch_sim.gd -- --policies default
##   godot --headless --path . -s res://tools/batch_sim.gd -- \
##       --policies greedy,smart,random --runs 100 --seed 1 --csv user://harness
##
##   --policies LIST   squad policies to compare on the same seeds, comma
##                     separated, or "default" for the harness's list. The
##                     scenario defaults to the harness's sandbox; --runs and
##                     --seed to the harness's. Prints a Markdown table and the
##                     exit checks; writes no stats log (the CSV holds every fight)
##   --csv DIR         write DIR/fights.csv and DIR/policies.csv; "none" to
##                     skip (default: the harness's csv_dir)
## Exits 0 on success, 1 when the scenario cannot be read or played.


const USAGE := "Usage: godot --headless --path . -s res://tools/batch_sim.gd -- --scenario PATH [--runs N] [--seed N] [--log PATH|none] [--policies default|NAME,NAME,... [--csv DIR|none]]"


func _initialize() -> void:
	quit(main(OS.get_cmdline_user_args()))


static func main(args: PackedStringArray) -> int:
	var settings := DevToolSettings.load_default()
	var opts := CliOptions.parse(args, {"runs": "", "seed": "", "log": "", "scenario": "", "policies": "",
		"csv": ""})
	if opts.is_empty():
		return 1
	if not str(opts.policies).is_empty():
		return compare(opts)
	opts.runs = opts.runs if not str(opts.runs).is_empty() else str(settings.default_runs)
	opts.seed = opts.seed if not str(opts.seed).is_empty() else str(settings.default_base_seed)
	opts.log = opts.log if not str(opts.log).is_empty() else settings.stats_log_path
	if opts.scenario.is_empty():
		printerr(USAGE)
		return 1
	var scenario := ScenarioFiles.load_scenario(opts.scenario)
	if scenario == null:
		printerr("Cannot read scenario %s" % opts.scenario)
		return 1
	var log_path: String = "" if opts.log == "none" else opts.log
	var report := BatchSimulator.run(scenario, int(opts.runs), int(opts.seed), log_path)
	print(report.format_text())
	if not report.problems.is_empty():
		return 1
	if not log_path.is_empty():
		print("Appended %d records to %s" % [report.runs, ProjectSettings.globalize_path(log_path)])
	return 0


## The policy comparison for --policies. Returns the exit code.
static func compare(opts: Dictionary) -> int:
	var harness := HarnessSettings.load_default()
	if harness == null:
		return 1
	var names: Array[String] = []
	if opts.policies == "default":
		names.assign(harness.policies)
	else:
		for n in str(opts.policies).split(",", false):
			names.append(n.strip_edges())
	var path: String = opts.scenario if not str(opts.scenario).is_empty() else harness.scenario
	var scenario := ScenarioFiles.load_scenario(path)
	if scenario == null:
		printerr("Cannot read scenario %s" % path)
		return 1
	var runs := int(opts.runs) if not str(opts.runs).is_empty() else harness.runs
	var seed_value := int(opts.seed) if not str(opts.seed).is_empty() else harness.base_seed
	var cmp := PolicyComparison.run(scenario, names, runs, seed_value, harness)
	print(cmp.format_text())
	if not cmp.problems.is_empty():
		return 1
	var csv_dir: String = opts.csv if not str(opts.csv).is_empty() else harness.csv_dir
	if csv_dir != "none":
		var err := cmp.write_csv(csv_dir)
		if err != OK:
			printerr("Cannot write CSV to %s: %s" % [csv_dir, error_string(err)])
			return 1
		print("Wrote %s and policies.csv" % ProjectSettings.globalize_path(csv_dir.path_join("fights.csv")))
	return 0
