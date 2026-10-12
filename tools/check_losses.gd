extends SceneTree
## Command line loss report: expected losses per act for auto-played
## campaigns, blind and careful autoplay under each loss-limit option. See
## LossReport.
##
##   godot --headless --path . -s res://tools/check_losses.gd -- --runs 40
##
## Options:
##   --runs N        campaigns per row (default: campaign_compare_runs)
##   --seed N        seed of the first run; run i uses seed + i
##   --markdown 1    print a Markdown table instead
## Exits 0 on success, 1 on a bad option or a broken run.


func _initialize() -> void:
	quit(main(OS.get_cmdline_user_args()))


static func main(args: PackedStringArray) -> int:
	var settings := DevToolSettings.load_default()
	var opts := {"runs": str(settings.campaign_compare_runs), "seed": str(settings.default_base_seed), "markdown": "0"}
	var i := 0
	while i < args.size():
		var key := args[i].trim_prefix("--")
		if not opts.has(key) or i + 1 >= args.size():
			printerr("Unknown or incomplete option: %s" % args[i])
			printerr("Usage: godot --headless --path . -s res://tools/check_losses.gd -- [--runs N] [--seed N] [--markdown 1]")
			return 1
		opts[key] = args[i + 1]
		i += 2
	var report := LossReport.run(int(opts.runs), int(opts.seed))
	print(report.format_markdown() if opts.markdown == "1" else report.format_text())
	return 0 if report.problems.is_empty() else 1
