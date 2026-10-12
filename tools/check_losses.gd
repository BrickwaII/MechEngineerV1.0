extends SceneTree
## Command line loss report: expected losses per act for auto-played
## campaigns, blind and careful autoplay under each loss-limit option. See
## LossReport.
##
##   godot --headless --path . -s res://tools/check_losses.gd -- --runs 40
##   godot --headless --path . -s res://tools/check_losses.gd -- --policy careful \
##       --sets "default;loss-count=attacks_only;loss-limit=scaled"
##
## Options:
##   --runs N        campaigns per row (default: campaign_compare_runs)
##   --policy NAME   blind, careful or all (default all)
##   --sets LIST     switch sets, ";"-separated, each "default" or
##                   "decision=option,decision=option" (default: the loss-limit options)
##   --seed N        seed of the first run; run i uses seed + i
##   --markdown 1    print a Markdown table instead
## Exits 0 on success, 1 on a bad option or a broken run.


func _initialize() -> void:
	quit(main(OS.get_cmdline_user_args()))


static func main(args: PackedStringArray) -> int:
	var settings := DevToolSettings.load_default()
	var opts := {"runs": str(settings.campaign_compare_runs), "seed": str(settings.default_base_seed), "markdown": "0",
		"policy": "all", "sets": ""}
	var i := 0
	while i < args.size():
		var key := args[i].trim_prefix("--")
		if not opts.has(key) or i + 1 >= args.size():
			printerr("Unknown or incomplete option: %s" % args[i])
			printerr("Usage: godot --headless --path . -s res://tools/check_losses.gd -- [--runs N] [--seed N] [--markdown 1]")
			return 1
		opts[key] = args[i + 1]
		i += 2
	var policies: Array[String] = CampaignAutoplay.POLICIES.duplicate()
	if opts.policy != "all":
		policies = [opts.policy]
	var sets: Array[Dictionary] = LossReport.DEFAULT_SETS.duplicate()
	if not String(opts.sets).is_empty():
		sets = []
		for text in String(opts.sets).split(";", false):
			var choices := {}
			if text.strip_edges() != "default":
				for pair in text.split(",", false):
					if not "=" in pair:
						printerr("A switch set wants decision=option, got %s" % pair)
						return 1
					choices[pair.get_slice("=", 0).strip_edges()] = pair.get_slice("=", 1).strip_edges()
			sets.append(choices)
	var report := LossReport.run(int(opts.runs), int(opts.seed), policies, sets)
	print(report.format_markdown() if opts.markdown == "1" else report.format_text())
	return 0 if report.problems.is_empty() else 1
