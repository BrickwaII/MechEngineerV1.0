extends SceneTree
## Command line variant comparison: the same seeded fights under every option
## of one switchboard decision, side by side. See VariantComparison.
##
##   godot --headless --path . -s res://tools/compare_variants.gd -- --decision d-wait --runs 200
##
## Options (defaults in data/scenarios/_dev_tools.json):
##   --decision ID   d-wait, d-wait-length, d-elasticity, d-personality-map,
##                   hp-carryover or draft-rule (required)
##   --runs N        runs per option
##   --seed N        seed of the first run; run i uses seed + i
##   --level N       enemy defense level, 0 to 5
##   --policy NAME   the squad's policy: simple, random, intent or patient
##   --enemy-policy NAME  the enemies' policy
##   --chain N       fights per run for hp-carryover
## Exits 0 on success, 1 on a bad option or decision.


func _initialize() -> void:
	quit(main(OS.get_cmdline_user_args()))


static func main(args: PackedStringArray) -> int:
	var settings := DevToolSettings.load_default()
	var opts := {"decision": "", "runs": str(settings.default_runs), "seed": str(settings.default_base_seed),
		"level": str(settings.compare_defense_level), "policy": settings.compare_player_policy,
		"enemy-policy": settings.compare_enemy_policy,
		"chain": str(settings.compare_chain_fights)}
	var i := 0
	while i < args.size():
		var key := args[i].trim_prefix("--")
		if not opts.has(key) or i + 1 >= args.size():
			printerr("Unknown or incomplete option: %s" % args[i])
			return 1
		opts[key] = args[i + 1]
		i += 2
	if opts.decision.is_empty():
		printerr("Usage: godot --headless --path . -s res://tools/compare_variants.gd -- --decision ID [--runs N] [--seed N] [--level N] [--policy NAME] [--enemy-policy NAME] [--chain N]")
		printerr("Decisions: " + ", ".join(VariantComparison.comparable()))
		return 1
	var cmp := VariantComparison.run(opts.decision, int(opts.runs), int(opts.seed), int(opts.level), opts.policy, opts["enemy-policy"], int(opts.chain))
	print(cmp.format_text())
	return 0 if cmp.problems.is_empty() else 1
