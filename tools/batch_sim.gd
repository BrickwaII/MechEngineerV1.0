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
## Exits 0 on success, 1 when the scenario cannot be read or played.


func _initialize() -> void:
	quit(main(OS.get_cmdline_user_args()))


static func main(args: PackedStringArray) -> int:
	var settings := DevToolSettings.load_default()
	var opts := {"runs": str(settings.default_runs), "seed": str(settings.default_base_seed),
		"log": settings.stats_log_path, "scenario": ""}
	var i := 0
	while i < args.size():
		var key := args[i].trim_prefix("--")
		if not opts.has(key) or i + 1 >= args.size():
			printerr("Unknown or incomplete option: %s" % args[i])
			return 1
		opts[key] = args[i + 1]
		i += 2
	if opts.scenario.is_empty():
		printerr("Usage: godot --headless --path . -s res://tools/batch_sim.gd -- --scenario PATH [--runs N] [--seed N] [--log PATH|none]")
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
