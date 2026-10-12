class_name LossReport
extends RefCounted
## Expected losses per act: auto-played campaigns (CampaignAutoplay) under
## each autoplay policy (blind: the weakest region in range; careful: by the
## map's odds, breaching Risky regions) and each loss-limit option compared,
## on the same seeds. Per act: runs that reached it, its loss limit, battles
## fought and won, mean losses, and runs the loss limit ended there.
##
##   var report := LossReport.run(40, 1)
##   print(report.format_text())
##
## The autoplay squad never grows and plays SimpleFightPolicy, so a person
## should lose less: read these as floors. TODO(decision: loss-limit),
## TODO(decision: difficulty-targets).

## Loss-limit options compared, the default first.
const LIMIT_OPTIONS: Array[String] = [CampaignVariants.LOSSES_THREE_PER_ACT, CampaignVariants.LOSSES_SCALED]
const ACTS := 3


## One act's totals for one policy and limit option.
class ActRow:
	var reached := 0
	var limit := 0
	var fights := 0
	var losses := 0
	var limit_hits := 0

	func mean_losses() -> float:
		return float(losses) / reached if reached > 0 else 0.0

	func win_percent() -> float:
		return 100.0 * (fights - losses) / fights if fights > 0 else 0.0

	func limit_hit_percent() -> float:
		return 100.0 * limit_hits / reached if reached > 0 else 0.0


## One policy and limit option.
class Cell:
	var policy := ""
	var limit_option := ""
	var acts: Array[ActRow] = []
	var boss_fought := 0
	var boss_won := 0
	var breaches := 0


var runs := 0
var base_seed := 0
var cells: Array[Cell] = []
var problems: Array[String] = []


static func run(p_runs: int, p_base_seed: int, policies: Array[String] = CampaignAutoplay.POLICIES,
		limit_options: Array[String] = LIMIT_OPTIONS) -> LossReport:
	var report := LossReport.new()
	report.runs = maxi(0, p_runs)
	report.base_seed = p_base_seed
	for policy in policies:
		if not policy in CampaignAutoplay.POLICIES:
			report.problems.append("unknown policy '%s' (use %s)" % [policy, ", ".join(CampaignAutoplay.POLICIES)])
	for option in limit_options:
		if not CampaignVariants.defaults().choose(CampaignVariants.LOSS_LIMIT, option):
			report.problems.append("unknown loss-limit option '%s'" % option)
	if not report.problems.is_empty():
		return report
	for policy in policies:
		for option in limit_options:
			report.cells.append(report._play(policy, option))
	return report


func _play(policy: String, option: String) -> Cell:
	var cell := Cell.new()
	cell.policy = policy
	cell.limit_option = option
	for a in ACTS:
		cell.acts.append(ActRow.new())
	var variants := CampaignVariants.defaults()
	variants.choose(CampaignVariants.LOSS_LIMIT, option)
	for i in runs:
		var autoplay := CampaignAutoplay.new(variants)
		autoplay.policy = policy
		var r := autoplay.play(base_seed + i)
		problems.append_array(r.problems)
		for a in mini(ACTS, r.losses_per_act.size()):
			var row := cell.acts[a]
			row.reached += 1
			row.limit = r.limit_per_act[a]
			row.fights += r.fights_per_act[a]
			row.losses += r.losses_per_act[a]
			if r.ended == Stakes.END_LOSS_LIMIT and a == r.losses_per_act.size() - 1:
				row.limit_hits += 1
		cell.breaches += r.breaches
		if r.boss_fought:
			cell.boss_fought += 1
			cell.boss_won += 1 if r.boss_won else 0
	return cell


func format_text() -> String:
	var lines := PackedStringArray()
	if not problems.is_empty() and cells.is_empty():
		lines.append("Cannot report losses:")
		for p in problems:
			lines.append("  - " + p)
		return "\n".join(lines)
	lines.append("Expected losses: %d auto-played campaigns per row (seeds %d to %d). The autoplay squad never grows: floors, not promises." % [
		runs, base_seed, base_seed + runs - 1])
	lines.append("%-8s %-14s %4s %8s %6s %7s %8s %11s %10s" % [
		"policy", "loss limit", "act", "reached", "limit", "fights", "win/fight", "mean losses", "limit hit"])
	for cell in cells:
		for a in cell.acts.size():
			var row := cell.acts[a]
			lines.append("%-8s %-14s %4d %8d %6s %7d %8.0f%% %11.2f %9.0f%%" % [
				cell.policy, cell.limit_option, a + 1, row.reached, str(row.limit) if row.reached > 0 else "-",
				row.fights, row.win_percent(), row.mean_losses(), row.limit_hit_percent()])
		lines.append("%-8s %-14s boss: fought %d, won %d; breaches %d" % [
			cell.policy, cell.limit_option, cell.boss_fought, cell.boss_won, cell.breaches])
	if not problems.is_empty():
		lines.append("Problems: " + "; ".join(problems))
	return "\n".join(lines)


## The same table as Markdown, for a pull request.
func format_markdown() -> String:
	var lines := PackedStringArray()
	lines.append("| Policy | Loss limit | Act | Reached | Limit | Win/fight | Mean losses | Limit hit |")
	lines.append("|---|---|---|---|---|---|---|---|")
	for cell in cells:
		for a in cell.acts.size():
			var row := cell.acts[a]
			if row.reached == 0:
				continue
			lines.append("| %s | %s | %d | %d | %d | %.0f%% | %.2f | %.0f%% |" % [
				cell.policy, cell.limit_option, a + 1, row.reached, row.limit, row.win_percent(),
				row.mean_losses(), row.limit_hit_percent()])
	return "\n".join(lines)
