extends SceneTree
## Prints the odds calibration table (OddsCalibration) as markdown.
##
##   godot --headless --path . -s res://tools/odds_calibration_cli.gd -- --squads 10 --regions 4 --seed 1


func _initialize() -> void:
	var opts := {"squads": "10", "regions": "4", "seed": "1"}
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i + 1 < args.size():
		opts[args[i].trim_prefix("--")] = args[i + 1]
		i += 2
	var started := Time.get_ticks_msec()
	var c := OddsCalibration.run(int(opts.squads), int(opts.regions), int(opts.seed))
	print(c.format_markdown())
	print("\n%d estimates of %d fights each in %.1f s; mean %.0f ms, slowest %d ms per estimate." % [
		c.samples.size(), OddsTuning.load_default().runs, (Time.get_ticks_msec() - started) / 1000.0,
		float(c.msec_total) / maxi(c.samples.size(), 1), c.msec_max])
	quit(0)
