class_name BatchSimulator
extends RefCounted
## Runs a scenario many times headless, with seeds base_seed, base_seed + 1, ...
## and totals the results. Each fight appends a record to the stats log unless
## `log_path` is empty. Tunings default to the ones in data/.


static func run(
	scenario: FightScenario,
	runs: int,
	base_seed: int,
	log_path := "",
	bot_tuning: BotTuning = null,
	enemy_table: EnemyTable = null,
	combat_tuning: CombatTuning = null,
) -> BatchReport:
	var resolved := scenario.resolve(bot_tuning, enemy_table, combat_tuning)
	if not resolved.is_playable():
		var failed := BatchReport.from_records(scenario.scenario_name, base_seed, [])
		failed.problems = resolved.problems
		return failed
	var records: Array[Dictionary] = []
	for i in maxi(0, runs):
		records.append(resolved.start(base_seed + i).run_to_end().record(scenario.scenario_name))
	if not log_path.is_empty():
		var err := FightStatsLog.append_all(log_path, records)
		if err != OK:
			push_error("BatchSimulator: cannot write %s (%s)" % [log_path, error_string(err)])
	return BatchReport.from_records(scenario.scenario_name, base_seed, records)
