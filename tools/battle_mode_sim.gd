extends SceneTree
## Plays whole Battle Mode runs headless (BattleModeRun), fight after fight
## with growth carried forward, and prints the end-of-run summary: turns, HP
## lost, energy spent and wasted, action-use share, combos and Staggers.
##
##   godot --headless --path . -s res://tools/battle_mode_sim.gd -- \
##       --fights 10 --seed 7 --policy simple
##
## Options:
##   --length ID     gauntlet (default) or endless (data/battle_mode/battle_mode.json)
##   --fights N      stop after N fights (0: until the run ends; endless needs a cap
##                   or a losing squad). Default: the length's own count, else 10
##   --seed N        run seed: every encounter and fight seed comes from it (default 1)
##   --runs N        play N runs with seeds seed, seed+1, ... (default 1)
##   --squad ID      a preset squad id, or "draft:SEED" for the first squad of a draft
##                   (default: the first preset)
##   --policy NAME   who plays the squad: simple, patient, intent, random (default simple)
##   --enemy NAME    who plays the enemies (default intent, as on screen)
##   --csv DIR       append fights.csv and runs.csv here; "none" to skip
##                   (default data's csv_folder, user://battle_mode)
## Exits 0 on success, 1 on a bad option.

const USAGE := "Usage: godot --headless --path . -s res://tools/battle_mode_sim.gd -- [--length gauntlet|endless] [--fights N] [--seed N] [--runs N] [--squad ID|draft:SEED] [--policy NAME] [--enemy NAME] [--csv DIR|none]"


func _initialize() -> void:
	quit(main(OS.get_cmdline_user_args()))


static func main(args: PackedStringArray) -> int:
	var tuning := BattleModeTuning.load_default()
	var opts := CliOptions.parse(args, {"length": "gauntlet", "fights": "", "seed": "1", "runs": "1",
		"squad": tuning.squads[0].id if not tuning.squads.is_empty() else "draft:1", "policy": "simple",
		"enemy": "intent", "csv": tuning.csv_folder}, USAGE)
	if opts.is_empty():
		return 1
	var length := tuning.length(opts.length)
	if length == null:
		printerr("Unknown length %s (use %s)" % [opts.length, ", ".join(tuning.lengths.keys())])
		return 1
	var problems: Array[String] = []
	var player := FightScenario.make_policy(opts.policy, problems)
	var enemy := FightScenario.make_policy(opts.enemy, problems)
	if not problems.is_empty():
		printerr("\n".join(problems))
		return 1
	var fights := int(opts.fights) if not str(opts.fights).is_empty() else (length.fights if not length.is_endless() else 10)
	for i in maxi(1, int(opts.runs)):
		var run_seed := int(opts.seed) + i
		var squad := squad_for(opts.squad, tuning)
		if squad == null:
			printerr("Unknown squad %s (use %s or draft:SEED)" % [opts.squad,
				", ".join(tuning.squads.map(func(p: BattleModeTuning.SquadPreset) -> String: return p.id))])
			return 1
		var run := BattleModeRun.create(squad, length.id, run_seed, FightVariants.defaults(), tuning)
		run.squad_label = opts.squad
		run.policy = opts.policy
		var summary := run.play_to_end(player, enemy, fights)
		print(summary.format_text(run.action_name))
		print("")
		if opts.csv != "none":
			var err := run.write_csv(opts.csv)
			if err != OK:
				printerr("Cannot write CSV to %s: %s" % [opts.csv, error_string(err)])
				return 1
	if opts.csv != "none":
		print("Appended to %s" % ProjectSettings.globalize_path(str(opts.csv).path_join("fights.csv")))
	return 0


## A preset's squad, or the first squad of a draft for "draft:SEED".
static func squad_for(label: String, tuning: BattleModeTuning) -> BotSquad:
	if label.begins_with("draft:"):
		return BotFactory.new(BotTuning.load_default()).build_squad(int(label.trim_prefix("draft:")))
	return BattleModeRun.preset_squad(label, tuning)
