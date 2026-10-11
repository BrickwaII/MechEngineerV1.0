extends SceneTree
## Command line variant comparison: the same seeded fights under every option
## of one switchboard decision, side by side. See VariantComparison. A
## campaign decision plays whole auto-played campaigns instead
## (CampaignComparison).
##
##   godot --headless --path . -s res://tools/compare_variants.gd -- --decision d-wait --runs 200
##   godot --headless --path . -s res://tools/compare_variants.gd -- --decision auto-expansion
##
## Options (defaults in data/scenarios/_dev_tools.json):
##   --decision ID   d-wait, d-wait-length, d-elasticity, d-personality-map,
##                   hp-carryover, skill-progression, tag-weight or draft-rule; or a campaign decision:
##                   energy-grid, grid-cost-owner, squad-size, act-pacing,
##                   auto-expansion (required)
##   --runs N        runs per option (campaigns: campaign_compare_runs)
##   --seed N        seed of the first run; run i uses seed + i
##   --level N       enemy defense level, 0 to 5
##   --policy NAME   the squad's policy: simple, random, intent or patient
##   --enemy-policy NAME  the enemies' policy
##   --chain N       fights per run for hp-carryover, skill-progression, tag-weight
## --level, --policy, --enemy-policy and --chain apply to fight decisions only.
## Exits 0 on success, 1 on a bad option or decision.


func _initialize() -> void:
	quit(main(OS.get_cmdline_user_args()))


static func main(args: PackedStringArray) -> int:
	var settings := DevToolSettings.load_default()
	var opts := {"decision": "", "runs": "", "seed": str(settings.default_base_seed),
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
		printerr("Decisions: " + ", ".join(VariantComparison.comparable() + CampaignComparison.comparable()))
		return 1
	if opts.decision in CampaignComparison.comparable():
		var runs: int = settings.campaign_compare_runs if opts.runs.is_empty() else int(opts.runs)
		var campaign_cmp := CampaignComparison.run(opts.decision, runs, int(opts.seed))
		print(campaign_cmp.format_text())
		return 0 if campaign_cmp.problems.is_empty() else 1
	if opts.runs.is_empty():
		opts.runs = str(settings.default_runs)
	var cmp := VariantComparison.run(opts.decision, int(opts.runs), int(opts.seed), int(opts.level), opts.policy, opts["enemy-policy"], int(opts.chain))
	print(cmp.format_text())
	return 0 if cmp.problems.is_empty() else 1
