extends SceneTree
## Command line balance sim: win rates of drafted squads against each act's
## early and late fights and the boss, next to the target bands in
## data/combat/difficulty_targets.json. See BalanceCurve.
##
##   godot --headless --path . -s res://tools/balance_sim.gd -- --runs 100
##   godot --headless --path . -s res://tools/balance_sim.gd -- --set speed-range=wide,strike-cost=free
##
## Options:
##   --runs N        runs per case (default: the data file's runs)
##   --seed N        seed of the first run; run i uses seed + i
##   --set LIST      fight switches to play, decision=option[,decision=option]
##   --old 1         play the behaviour before the combat-economy pass:
##                   speed-range=wide, strike-cost=free, tag-weight=per_action,
##                   difficulty-curve=flat
##   --markdown 1    print a Markdown table instead
##   --targets PATH  another targets file (default data/combat/difficulty_targets.json)
## Exits 0 on success, 1 on a bad option or unreadable data.

## The switches before the combat-economy pass (R2-C).
const OLD_CHOICES := {"speed-range": "wide", "strike-cost": "free", "tag-weight": "per_action",
	"difficulty-curve": "flat"}


func _initialize() -> void:
	quit(main(OS.get_cmdline_user_args()))


static func main(args: PackedStringArray) -> int:
	var settings := DevToolSettings.load_default()
	var opts := {"runs": "-1", "seed": str(settings.default_base_seed), "set": "", "old": "0", "markdown": "0",
		"targets": BalanceCurve.DEFAULT_PATH}
	var i := 0
	while i < args.size():
		var key := args[i].trim_prefix("--")
		if not opts.has(key) or i + 1 >= args.size():
			printerr("Unknown or incomplete option: %s" % args[i])
			printerr("Usage: godot --headless --path . -s res://tools/balance_sim.gd -- [--runs N] [--seed N] [--set d=o,...] [--old 1] [--markdown 1]")
			return 1
		opts[key] = args[i + 1]
		i += 2
	var choices := OLD_CHOICES.duplicate() if opts.old == "1" else {}
	for pair in String(opts.set).split(",", false):
		if not "=" in pair:
			printerr("--set wants decision=option, got %s" % pair)
			return 1
		choices[pair.get_slice("=", 0).strip_edges()] = pair.get_slice("=", 1).strip_edges()
	var curve := BalanceCurve.run(int(opts.runs), int(opts.seed), choices, opts.targets)
	if not curve.problems.is_empty():
		printerr(curve.format_text())
		return 1
	print(curve.format_markdown() if opts.markdown == "1" else curve.format_text())
	return 0
