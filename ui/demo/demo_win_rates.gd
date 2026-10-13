class_name DemoWinRates
extends RefCounted
## How winnable each demo fight is: headless auto-fights (HeadlessFightRunner)
## of the scenario's squad against its enemies, under the shipped default
## switches, over many seeds. The player plays a policy (simple by default),
## enemies play by intent as on the battle screen. A stand-in for a person,
## who plays better than the simple policy.
##
## From the command line:
##   godot --headless --path . -s res://ui/demo/demo_win_rates_cli.gd -- [runs] [policy]

const DEFAULT_RUNS := 60


## {"wins": n, "runs": n, "rate": percent, "shown_seed_won": bool} for one
## fight scenario. `shown_seed_won` is the fight the demo itself plays (the
## battle screen's seed for the request).
static func measure(s: DemoScenario, runs := DEFAULT_RUNS, policy := "simple") -> Dictionary:
	var problems: Array[String] = []
	var squad := BotSquadProvider.new(s.build_squad(problems)).get_squad()
	var request := s.fight_request(squad)
	var table := s.enemy_table(problems)
	var tuning := CombatTuning.load_default().with_variants(FightVariants.defaults())
	var wins := 0
	var hp_left := 0.0
	for i in runs:
		var fight := _play(request, 1000 + i, policy, tuning, table)
		if fight.outcome == FightResult.Outcome.VICTORY:
			wins += 1
			hp_left += _hp_left(fight)
	var shown := _play(request, hash("%s:%d:%d" % [request.territory_id, request.kind, request.defense_level]),
		policy, tuning, table)
	return {
		"wins": wins, "runs": runs, "rate": 100.0 * wins / maxi(1, runs),
		"hp_left": 100.0 * hp_left / maxi(1, wins),
		"shown_seed_won": shown.outcome == FightResult.Outcome.VICTORY,
		"problems": problems,
	}


static func _play(request: FightRequest, seed_value: int, policy: String, tuning: CombatTuning, table: EnemyTable) -> Fight:
	var unused: Array[String] = []
	return HeadlessFightRunner.run(request, seed_value, FightScenario.make_policy(policy, unused),
		IntentFightPolicy.new(), tuning, table)


## The squad's hp left over its max hp, 0 to 1.
static func _hp_left(fight: Fight) -> float:
	var hp := 0
	var max_hp := 0
	for c in fight.combatants:
		if c.side == Combatant.Side.PLAYER:
			hp += maxi(0, c.hp)
			max_hp += c.max_hp
	return float(hp) / maxi(1, max_hp)


## One line per fight scenario in `dir`.
static func report(runs := DEFAULT_RUNS, policy := "simple", dir := DemoScenario.DEFAULT_DIR) -> PackedStringArray:
	var out := PackedStringArray()
	for s in DemoScenario.load_all(dir):
		if not s.is_fight():
			continue
		var r := measure(s, runs, policy)
		out.append("%-12s %-12s level %d  ranks %d  %5.1f%% (%d/%d), %3.0f%% hp left in wins, shown fight %s" % [
			s.id, s.scenario_name, int(s.fight.get("level", 0)), int(s.squad.get("skill_ranks", 0)),
			r.rate, r.wins, r.runs, r.hp_left, "won" if r.shown_seed_won else "lost"])
	return out
