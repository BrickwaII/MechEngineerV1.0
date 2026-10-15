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

const USAGE := "Usage: godot --headless --path . -s res://tools/check_losses.gd -- [--runs N] [--seed N] [--markdown 1]"


func _initialize() -> void:
	quit(main(OS.get_cmdline_user_args()))


static func main(args: PackedStringArray) -> int:
	var settings := DevToolSettings.load_default()
	var opts := CliOptions.parse(args, {"runs": str(settings.campaign_compare_runs), "seed": str(settings.default_base_seed), "markdown": "0",
		"policy": "all", "sets": ""}, USAGE)
	if opts.is_empty():
		return 1
	var policies: Array[String] = CampaignAutoplay.POLICIES.duplicate()
	if opts.policy != "all":
		policies = [opts.policy]
	var sets: Array[Dictionary] = LossReport.DEFAULT_SETS.duplicate()
	if not String(opts.sets).is_empty():
		sets = []
		for text in String(opts.sets).split(";", false):
			var choices := {}
			if text.strip_edges() != "default" and not CliOptions.parse_choices(text, choices, "A switch set wants"):
				return 1
			sets.append(choices)
	var report := LossReport.run(int(opts.runs), int(opts.seed), policies, sets)
	print(report.format_markdown() if opts.markdown == "1" else report.format_text())
	return 0 if report.problems.is_empty() else 1
