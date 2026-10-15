extends SceneTree
## Command line faction check: win rates at defense levels 0 to 5 for every
## enemy faction in every act's tiers, next to today's generic enemies. See
## FactionWinRates.
##
##   godot --headless --path . -s res://tools/check_factions.gd -- --runs 100
##
## Options (defaults in data/scenarios/_dev_tools.json):
##   --runs N        runs per cell
##   --seed N        seed of the first run; run i uses seed + i
##   --markdown 1    print a Markdown table instead
## Exits 0 on success, 1 on a bad option or a broken faction table.

const USAGE := "Usage: godot --headless --path . -s res://tools/check_factions.gd -- [--runs N] [--seed N] [--markdown 1]"


func _initialize() -> void:
	quit(main(OS.get_cmdline_user_args()))


static func main(args: PackedStringArray) -> int:
	var settings := DevToolSettings.load_default()
	var opts := CliOptions.parse(args, {"runs": str(settings.default_runs), "seed": str(settings.default_base_seed), "markdown": "0"}, USAGE)
	if opts.is_empty():
		return 1
	var rates := FactionWinRates.run(int(opts.runs), int(opts.seed))
	print(rates.format_markdown() if opts.markdown == "1" and rates.problems.is_empty() else rates.format_text())
	return 0 if rates.problems.is_empty() else 1
