extends SceneTree
## Prints each demo fight's win rate (DemoWinRates):
##   godot --headless --path . -s res://ui/demo/demo_win_rates_cli.gd -- [runs] [policy]
## policy: simple (default), random, intent or patient.


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var runs := int(args[0]) if args.size() > 0 else DemoWinRates.DEFAULT_RUNS
	var policy := str(args[1]) if args.size() > 1 else "simple"
	print("Demo fight win rates, %d seeds each, player policy %s:" % [runs, policy])
	for line in DemoWinRates.report(runs, policy):
		print("  " + line)
	quit()
