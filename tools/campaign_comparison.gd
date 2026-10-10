class_name CampaignComparison
extends RefCounted
## Plays the same seeded campaigns under every option of one campaign
## decision (CampaignAutoplay) and totals each option: acts cleared, days
## used, fights fought, forced defenses, and more, side by side.
##
##   var cmp := CampaignComparison.run("auto-expansion", 50, 1)
##   print(cmp.format_text())
##
## Run i plays seed base_seed + i under every option, so every option meets
## the same squads, starts and fight seeds. Every other switch stays at its
## default.

const Spread := BatchReport.Spread

## One option's totals.
class OptionResult:
	var option := ""
	var is_default := false
	var records: Array[CampaignAutoplay.Record] = []
	var acts_cleared: Spread
	var days_used: Spread
	var fights: Spread
	var forced_defenses: Spread
	var actions: Spread
	var expansion_claims: Spread
	var end_grid: Spread
	## Share of runs that cleared every act, and that beat the boss.
	var all_acts_rate := 0.0
	var boss_win_rate := 0.0
	## Won attacks over all attacks.
	var attack_win_rate := 0.0


var decision := ""
var runs := 0
var base_seed := 0
var results: Array[OptionResult] = []
var problems: Array[String] = []


## Compares every option of campaign decision `p_decision`.
static func run(p_decision: String, p_runs: int, p_base_seed: int) -> CampaignComparison:
	var cmp := CampaignComparison.new()
	cmp.decision = p_decision
	cmp.runs = maxi(0, p_runs)
	cmp.base_seed = p_base_seed
	var options := options_of(p_decision)
	if options.is_empty():
		cmp.problems.append("unknown campaign decision '%s' (use %s)" % [p_decision, ", ".join(comparable())])
		return cmp
	for option in options:
		cmp.results.append(cmp._play_option(option))
	return cmp


## Every campaign decision this tool can compare.
static func comparable() -> Array[String]:
	var out: Array[String] = []
	for id: String in CampaignVariants.KNOWN:
		out.append(id)
	return out


## The options of `p_decision`, the default first; empty if it is unknown.
static func options_of(p_decision: String) -> Array[String]:
	var out: Array[String] = []
	var v := CampaignVariants.defaults()
	if not CampaignVariants.KNOWN.has(p_decision):
		return out
	out.append(v.option(p_decision))
	for option: String in (v.params_by_option[p_decision] as Dictionary):
		if not option in out:
			out.append(option)
	return out


func _play_option(option: String) -> OptionResult:
	var r := OptionResult.new()
	r.option = option
	var v := CampaignVariants.defaults()
	r.is_default = option == v.option(decision)
	v.choose(decision, option)
	# One set serves both: run decisions are read at the start, the fight one
	# when each fight starts.
	var player := CampaignAutoplay.new(v, v)
	var lists := {}
	for key in ["acts_cleared", "days_used", "fights", "forced_defenses", "actions", "expansion_claims", "end_grid"]:
		lists[key] = [] as Array[float]
	var all_acts := 0
	var boss_wins := 0
	var won := 0
	var attacks := 0
	var acts := ActPlan.load_file(CampaignAutoplay.ACTS_FILE).act_count()
	for i in runs:
		var rec := player.play(base_seed + i)
		for p in rec.problems:
			problems.append("%s=%s seed %d: %s" % [decision, option, rec.run_seed, p])
		r.records.append(rec)
		for key: String in lists:
			(lists[key] as Array[float]).append(float(rec.get(key)))
		if rec.acts_cleared >= acts:
			all_acts += 1
		if rec.boss_won:
			boss_wins += 1
		won += rec.attacks_won
		attacks += rec.attacks_won + rec.attacks_lost
	r.acts_cleared = Spread.of(lists.acts_cleared)
	r.days_used = Spread.of(lists.days_used)
	r.fights = Spread.of(lists.fights)
	r.forced_defenses = Spread.of(lists.forced_defenses)
	r.actions = Spread.of(lists.actions)
	r.expansion_claims = Spread.of(lists.expansion_claims)
	r.end_grid = Spread.of(lists.end_grid)
	r.all_acts_rate = float(all_acts) / runs if runs > 0 else 0.0
	r.boss_win_rate = float(boss_wins) / runs if runs > 0 else 0.0
	r.attack_win_rate = float(won) / attacks if attacks > 0 else 0.0
	return r


## The side-by-side table the command line prints.
func format_text() -> String:
	var lines := PackedStringArray()
	if not results.is_empty():
		lines.append("Campaign decision: %s, %d auto-played campaigns per option (seeds %d to %d)" % [
			decision, runs, base_seed, base_seed + runs - 1])
		lines.append("Policy: defend when forced; reinforce the most pressed region at %.0f pressure; else attack the weakest region in range if the grid holds its cost; else wait. * marks the default." % CampaignAutoplay.new().reinforce_at)
		lines.append("%-15s %13s %8s %13s %13s %13s %13s %8s %6s %11s %11s" % [
			"option", "acts cleared", "all 3", "days used", "fights", "forced def.", "actions", "atk won", "boss", "expansions", "end grid"])
		for r in results:
			lines.append("%-15s %13s %7.0f%% %13s %13s %13s %13s %7.0f%% %5.0f%% %11s %11s" % [
				r.option + ("*" if r.is_default else ""), r.acts_cleared.short_text(), 100.0 * r.all_acts_rate,
				r.days_used.short_text(), r.fights.short_text(), r.forced_defenses.short_text(), r.actions.short_text(),
				100.0 * r.attack_win_rate, 100.0 * r.boss_win_rate, r.expansion_claims.short_text(), r.end_grid.short_text()])
		lines.append("(mean ± spread per campaign; all 3 = runs that cleared every act; boss = runs that beat the stub boss)")
	if not problems.is_empty():
		lines.append("Problems:")
		for p in problems:
			lines.append("  - " + p)
	return "\n".join(lines)
