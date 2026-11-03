class_name PolicyComparison
extends RefCounted
## The simulation harness (combat rework S8): plays one scenario N times with
## each of several squad policies, on the same seeds, and compares them. Every
## number comes from the fight's own summary (FightSummary), so the harness,
## Battle Mode and the battle screen count the same things.
##
##   var cmp := PolicyComparison.run(scenario, ["greedy", "smart", "random"], 100, 1)
##   print(cmp.format_text())         # comparison table and the exit checks
##   cmp.write_csv("user://harness")  # fights.csv (one row per fight), policies.csv
##
## From a live or edited set-up (the battle debugger's "Simulate 100"), build a
## ResolvedScenario from the request, tuning and enemy table and call
## compare() with the policies by name.
##
## Exit checks (the deep dive's "tests that tell you if it's fun", thresholds
## in data/scenarios/_harness.json): greedy loses clearly more HP and capacity
## than clean play; no action above about 50% of the clean policy's uses; the
## clean-win gap on seeds both policies win. A check is skipped when its
## policies were not played.

## One policy's totals over its fights.
class PolicyRow:
	extends RefCounted
	var policy := ""
	var fights := 0
	var wins := 0
	var timeouts := 0
	## Sums over the fights; the mean_* functions divide.
	var hp_lost := 0
	var hp_start := 0
	var grid_cost := 0.0
	var energy_spent := 0.0
	var decisions := 0
	var ticks := 0
	var combos := 0
	var setups := 0
	var staggers := 0
	var downed := 0
	## Action id -> squad decisions, over every fight.
	var action_uses: Dictionary = {}
	## Fights in which one action took more than the share limit.
	var fights_over_share := 0

	func win_rate() -> float:
		return float(wins) / fights if fights > 0 else 0.0

	func mean(total: float) -> float:
		return total / fights if fights > 0 else 0.0

	## HP lost as a percent of the squad's starting HP, over every fight.
	func hp_lost_percent() -> float:
		return 100.0 * hp_lost / hp_start if hp_start > 0 else 0.0

	## Percent of all squad decisions that used `action_id`.
	func share_percent(action_id: String) -> float:
		return 100.0 * action_uses.get(action_id, 0) / decisions if decisions > 0 else 0.0

	## The most used action, "" when none.
	func top_action() -> String:
		var best := ""
		for id: String in PolicyComparison.sorted_keys(action_uses):
			if best.is_empty() or int(action_uses[id]) > int(action_uses[best]):
				best = id
		return best

	func to_dict() -> Dictionary:
		return {"policy": policy, "fights": fights, "wins": wins, "timeouts": timeouts, "hp_lost": hp_lost,
			"hp_start": hp_start, "grid_cost": grid_cost, "energy_spent": energy_spent, "decisions": decisions,
			"ticks": ticks, "combos": combos, "setups": setups, "staggers": staggers, "downed": downed,
			"action_uses": FightSummary._sorted(action_uses), "fights_over_share": fights_over_share}


## One exit check's verdict.
class Check:
	extends RefCounted
	var id := ""
	## "pass", "fail" or "skipped".
	var verdict := "skipped"
	var detail := ""

	func passed() -> bool:
		return verdict == "pass"

	func to_dict() -> Dictionary:
		return {"id": id, "verdict": verdict, "detail": detail}


const CHECK_GREEDY := "greedy_loses_more"
const CHECK_SHARE := "action_share"
const CHECK_CLEAN_WIN := "clean_win_gap"

var scenario_name := ""
var base_seed := 0
var runs := 0
var settings: HarnessSettings
## One row per policy, in the order played.
var rows: Array[PolicyRow] = []
## One record per fight, policy by policy, seed by seed (see fight_record()).
var fights: Array[Dictionary] = []
var checks: Array[Check] = []
var problems: Array[String] = []


## Plays `scenario` `runs` times per policy (seeds base_seed, base_seed + 1,
## ...), its squad by each of `policy_names` (FightScenario names), its
## enemies by the scenario's enemy policy. Tunings and settings default to
## data/. Check `problems` first.
static func run(scenario: FightScenario, policy_names: Array[String], p_runs: int, p_base_seed: int,
		p_settings: HarnessSettings = null, bot_tuning: BotTuning = null, enemy_table: EnemyTable = null,
		combat_tuning: CombatTuning = null) -> PolicyComparison:
	var resolved := scenario.resolve(bot_tuning, enemy_table, combat_tuning)
	return compare(resolved, scenario.scenario_name, policy_names, p_runs, p_base_seed, p_settings)


## The comparison on an already resolved set-up: `resolved`'s request, tuning,
## enemy table and enemy policy; its player policy is replaced by each of
## `policy_names` in turn.
static func compare(resolved: ResolvedScenario, p_name: String, policy_names: Array[String], p_runs: int,
		p_base_seed: int, p_settings: HarnessSettings = null) -> PolicyComparison:
	var cmp := PolicyComparison.new()
	cmp.scenario_name = p_name
	cmp.base_seed = p_base_seed
	cmp.runs = maxi(0, p_runs)
	cmp.settings = p_settings if p_settings != null else HarnessSettings.load_default()
	cmp.problems.append_array(resolved.problems)
	for policy_name in policy_names:
		FightScenario.make_policy(policy_name, cmp.problems)
	if policy_names.is_empty():
		cmp.problems.append("no policies to compare")
	if not cmp.problems.is_empty():
		return cmp
	for i in policy_names.size():
		var row := PolicyRow.new()
		row.policy = policy_names[i]
		for n in cmp.runs:
			var seed_value := p_base_seed + n
			# A fresh policy per fight, so no fight leaks state into the next.
			var policy := FightScenario.make_policy(row.policy, cmp.problems)
			var sim := SimulatedFight.new(resolved.request, seed_value, policy, resolved.enemy_policy,
				resolved.tuning, resolved.enemy_table).run_to_end()
			var record := fight_record(row.policy, seed_value, sim.fight.summary())
			cmp._add(row, record)
			cmp.fights.append(record)
		cmp.rows.append(row)
	cmp._run_checks()
	return cmp


## One fight as a flat record: the CSV's row. Squad numbers only; shares are
## percent of the squad's decisions (FightSummary.Tally.share_percent).
static func fight_record(policy_name: String, seed_value: int, s: FightSummary) -> Dictionary:
	var top := ""
	for id: String in sorted_keys(s.squad.action_uses):
		if top.is_empty() or int(s.squad.action_uses[id]) > int(s.squad.action_uses[top]):
			top = id
	return {
		"policy": policy_name, "seed": seed_value, "won": s.is_victory(), "timed_out": s.timed_out,
		"decisions": s.squad.decisions, "all_decisions": s.decisions, "ticks": s.ticks,
		"hp_start": s.squad.hp_start, "hp_lost": s.squad.hp_lost(), "downed": s.squad.downed,
		"grid_cost": s.grid_cost, "energy_spent": s.squad.energy_spent(), "combos": s.squad.combos,
		"setups": s.squad.setups, "staggers": s.squad.staggers, "top_action": top,
		"top_share_percent": s.squad.share_percent(top) if not top.is_empty() else 0,
		"action_uses": FightSummary._sorted(s.squad.action_uses),
	}


func row(policy_name: String) -> PolicyRow:
	for r in rows:
		if r.policy == policy_name:
			return r
	return null


func check(check_id: String) -> Check:
	for c in checks:
		if c.id == check_id:
			return c
	return null


## Every action id the squad used in any fight, sorted.
func action_ids() -> Array[String]:
	var seen := {}
	for r in rows:
		for id: String in r.action_uses:
			seen[id] = true
	return sorted_keys(seen)


func _add(r: PolicyRow, rec: Dictionary) -> void:
	r.fights += 1
	r.wins += 1 if rec.won else 0
	r.timeouts += 1 if rec.timed_out else 0
	r.hp_lost += int(rec.hp_lost)
	r.hp_start += int(rec.hp_start)
	r.grid_cost += float(rec.grid_cost)
	r.energy_spent += float(rec.energy_spent)
	r.decisions += int(rec.decisions)
	r.ticks += int(rec.ticks)
	r.combos += int(rec.combos)
	r.setups += int(rec.setups)
	r.staggers += int(rec.staggers)
	r.downed += int(rec.downed)
	FightSummary._add_counts(r.action_uses, rec.action_uses)
	if int(rec.top_share_percent) > settings.max_action_share_percent:
		r.fights_over_share += 1


func _run_checks() -> void:
	var clean := row(settings.clean_policy)
	var careless := row(settings.careless_policy)
	var gap := 1.0 + settings.clear_gap_percent / 100.0
	var greedy := Check.new()
	greedy.id = CHECK_GREEDY
	if clean != null and careless != null and clean != careless:
		var hp_clean := clean.mean(clean.hp_lost)
		var hp_careless := careless.mean(careless.hp_lost)
		var grid_clean := clean.mean(clean.grid_cost)
		var grid_careless := careless.mean(careless.grid_cost)
		greedy.verdict = "pass" if hp_careless >= hp_clean * gap and hp_careless > hp_clean \
			and grid_careless > grid_clean else "fail"
		greedy.detail = "%s loses %s HP and %s capacity per fight, %s %s and %s (HP needs +%d%%)" % [
			careless.policy, _num(hp_careless), _num(grid_careless), clean.policy, _num(hp_clean),
			_num(grid_clean), settings.clear_gap_percent]
	else:
		greedy.detail = "needs %s and %s" % [settings.careless_policy, settings.clean_policy]
	checks.append(greedy)
	var share := Check.new()
	share.id = CHECK_SHARE
	if clean != null and clean.decisions > 0:
		var top := clean.top_action()
		share.verdict = "pass" if clean.share_percent(top) <= settings.max_action_share_percent else "fail"
		share.detail = "%s's top action %s is %s%% of its uses (limit %d%%); %d of %d fights over the limit" % [
			clean.policy, top, _num(clean.share_percent(top)), settings.max_action_share_percent,
			clean.fights_over_share, clean.fights]
	else:
		share.detail = "needs %s" % settings.clean_policy
	checks.append(share)
	var clean_win := Check.new()
	clean_win.id = CHECK_CLEAN_WIN
	if clean != null and careless != null and clean != careless:
		var both := 0
		var hp_clean := 0
		var hp_careless := 0
		var grid_clean := 0.0
		var grid_careless := 0.0
		var by_seed := {}
		for rec in fights:
			if rec.policy == clean.policy and rec.won:
				by_seed[rec.seed] = rec
		for rec in fights:
			if rec.policy == careless.policy and rec.won and by_seed.has(rec.seed):
				both += 1
				hp_careless += int(rec.hp_lost)
				grid_careless += float(rec.grid_cost)
				hp_clean += int(by_seed[rec.seed].hp_lost)
				grid_clean += float(by_seed[rec.seed].grid_cost)
		if both > 0:
			clean_win.verdict = "pass" if hp_careless >= hp_clean * gap and hp_careless > hp_clean else "fail"
			clean_win.detail = "on the %d seeds both win: %s loses %s HP and %s capacity, %s %s and %s" % [
				both, careless.policy, _num(float(hp_careless) / both), _num(grid_careless / both),
				clean.policy, _num(float(hp_clean) / both), _num(grid_clean / both)]
		else:
			clean_win.detail = "no seed that both %s and %s win" % [clean.policy, careless.policy]
	else:
		clean_win.detail = "needs %s and %s" % [settings.careless_policy, settings.clean_policy]
	checks.append(clean_win)


## The comparison table (Markdown, so it pastes into a PR) and the checks.
func format_text() -> String:
	var lines := PackedStringArray()
	if not problems.is_empty():
		lines.append("%s: cannot compare: %s" % [scenario_name, "; ".join(problems)])
		return "\n".join(lines)
	lines.append("%s: %d fights per policy, seeds %d to %d" % [scenario_name, runs, base_seed, base_seed + runs - 1])
	lines.append("")
	lines.append("| Policy | Win | HP lost | HP lost %% | Capacity | Energy | Length | Ticks | Combos | Staggers | Top action | Fights >%d%% | Action share |" % settings.max_action_share_percent)
	lines.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|")
	for r in rows:
		var top := r.top_action()
		lines.append("| %s | %s%% | %s | %s%% | %s | %s | %s | %s | %s | %s | %s %s%% | %d / %d | %s |" % [
			r.policy, _num(100.0 * r.win_rate()), _num(r.mean(r.hp_lost)), _num(r.hp_lost_percent()),
			_num(r.mean(r.grid_cost)), _num(r.mean(r.energy_spent)), _num(r.mean(r.decisions)), _num(r.mean(r.ticks)),
			_num(r.mean(r.combos)), _num(r.mean(r.staggers)), top if not top.is_empty() else "-",
			_num(r.share_percent(top)), r.fights_over_share, r.fights, _shares_text(r)])
	lines.append("")
	lines.append("Per fight: HP lost, capacity (grid cost), energy, length (squad decisions), ticks, combos, Staggers.")
	lines.append("")
	lines.append("Checks:")
	for c in checks:
		lines.append("- %s: %s. %s" % [c.id, c.verdict.to_upper(), c.detail])
	return "\n".join(lines)


func _shares_text(r: PolicyRow) -> String:
	var parts := PackedStringArray()
	for id in action_ids():
		if r.action_uses.has(id):
			parts.append("%s %s%%" % [id, _num(r.share_percent(id))])
	return ", ".join(parts) if not parts.is_empty() else "-"


const FIGHT_COLUMNS: Array[String] = ["scenario", "policy", "seed", "won", "timed_out", "decisions",
	"all_decisions", "ticks", "hp_start", "hp_lost", "downed", "grid_cost", "energy_spent", "combos", "setups",
	"staggers", "top_action", "top_share_percent"]
const POLICY_COLUMNS: Array[String] = ["scenario", "policy", "fights", "win_rate", "hp_lost", "hp_lost_percent",
	"grid_cost", "energy_spent", "decisions", "ticks", "combos", "setups", "staggers", "downed", "timeouts",
	"top_action", "top_share_percent", "fights_over_share"]


## The CSV header and rows of fights.csv: one row per fight, a share_<action>
## column (percent of the squad's decisions) per action used.
func fight_table() -> Array:
	var ids := action_ids()
	var header: Array = FIGHT_COLUMNS.duplicate()
	for id in ids:
		header.append("share_%s" % id)
	var out: Array = []
	for rec in fights:
		var line: Array = [scenario_name]
		for col in FIGHT_COLUMNS.slice(1):
			line.append(_cell(rec[col]))
		var decisions := int(rec.decisions)
		for id in ids:
			line.append(_num(100.0 * int(rec.action_uses.get(id, 0)) / decisions) if decisions > 0 else "0")
		out.append(line)
	return [header, out]


## The CSV header and rows of policies.csv: one row per policy (means per
## fight), then each exit check's verdict and a share_<action> column per action.
func policy_table() -> Array:
	var ids := action_ids()
	var header: Array = POLICY_COLUMNS.duplicate()
	for c in checks:
		header.append("check_%s" % c.id)
	for id in ids:
		header.append("share_%s" % id)
	var out: Array = []
	for r in rows:
		var top := r.top_action()
		var line: Array = [scenario_name, r.policy, r.fights, _num(r.win_rate()), _num(r.mean(r.hp_lost)),
			_num(r.hp_lost_percent()), _num(r.mean(r.grid_cost)), _num(r.mean(r.energy_spent)),
			_num(r.mean(r.decisions)), _num(r.mean(r.ticks)), _num(r.mean(r.combos)), _num(r.mean(r.setups)),
			_num(r.mean(r.staggers)), _num(r.mean(r.downed)), r.timeouts, top, _num(r.share_percent(top)),
			r.fights_over_share]
		for c in checks:
			line.append(c.verdict)
		for id in ids:
			line.append(_num(r.share_percent(id)))
		out.append(line)
	return [header, out]


## Writes `dir`/fights.csv and `dir`/policies.csv, replacing older ones (their
## columns follow the actions used). Returns the first error, or OK.
func write_csv(dir: String) -> Error:
	for pair: Array in [["fights.csv", fight_table()], ["policies.csv", policy_table()]]:
		var path: String = dir.path_join(pair[0])
		if FileAccess.file_exists(path):
			var removed := DirAccess.remove_absolute(path)
			if removed != OK:
				return removed
		var err := CsvFile.append(path, pair[1][0], pair[1][1])
		if err != OK:
			return err
	return OK


## Every field, for tests and the golden capture.
func to_dict() -> Dictionary:
	return {"scenario": scenario_name, "base_seed": base_seed, "runs": runs,
		"rows": rows.map(func(r: PolicyRow) -> Dictionary: return r.to_dict()),
		"checks": checks.map(func(c: Check) -> Dictionary: return c.to_dict()), "problems": problems}


static func sorted_keys(d: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for k: Variant in d:
		keys.append(str(k))
	keys.sort()
	return keys


static func _cell(v: Variant) -> String:
	if v is float:
		return _num(v)
	return str(v)


## A number with at most two decimals, trailing zeros dropped.
static func _num(v: float) -> String:
	var s := "%.2f" % v
	s = s.rstrip("0").rstrip(".") if "." in s else s
	return s if s != "-0" else "0"
