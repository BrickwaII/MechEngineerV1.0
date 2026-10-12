class_name LossReport
extends RefCounted
## Expected losses per act: auto-played campaigns (CampaignAutoplay) under
## each autoplay policy (blind: the weakest region in range; careful: by the
## map's odds, breaching Risky regions) and each set of campaign switches
## compared, on the same seeds. By default the sets are the loss-limit options. Per act: runs that reached it, its loss limit, battles
## fought and won, mean losses, and runs the loss limit ended there.
##
##   var report := LossReport.run(40, 1)
##   print(report.format_text())
##
## The autoplay squad grows as in a real run (skill ranks from PostFight) but
## plays SimpleFightPolicy, so a person should lose less: read these as floors. TODO(decision: loss-limit),
## TODO(decision: difficulty-targets).

## Switch sets compared by default: the loss-limit options, the default first.
const DEFAULT_SETS: Array[Dictionary] = [
	{},
	{CampaignVariants.LOSS_LIMIT: CampaignVariants.LOSSES_SCALED},
]
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


## One policy and switch set.
class Cell:
	var policy := ""
	## Decision id -> option id; {} is every default.
	var choices := {}
	var acts: Array[ActRow] = []
	var boss_fought := 0
	var boss_won := 0
	var breaches := 0


var runs := 0
var base_seed := 0
## Applies every fight to the autoplay squad (CampaignAutoplay.grow).
var grow := true
var cells: Array[Cell] = []
var problems: Array[String] = []


static func run(p_runs: int, p_base_seed: int, policies: Array[String] = CampaignAutoplay.POLICIES,
		sets: Array[Dictionary] = DEFAULT_SETS) -> LossReport:
	var report := LossReport.new()
	report.runs = maxi(0, p_runs)
	report.base_seed = p_base_seed
	for policy in policies:
		if not policy in CampaignAutoplay.POLICIES:
			report.problems.append("unknown policy '%s' (use %s)" % [policy, ", ".join(CampaignAutoplay.POLICIES)])
	for choices in sets:
		for decision: String in choices:
			if not CampaignVariants.defaults().choose(decision, str(choices[decision])):
				report.problems.append("unknown campaign option %s=%s" % [decision, choices[decision]])
	if not report.problems.is_empty():
		return report
	for policy in policies:
		for choices in sets:
			report.cells.append(report._play(policy, choices))
	return report


## "default", or "decision=option, ..." for a switch set.
static func set_name(choices: Dictionary) -> String:
	if choices.is_empty():
		return "default"
	var parts := PackedStringArray()
	for decision: String in choices:
		parts.append("%s=%s" % [decision, choices[decision]])
	return ", ".join(parts)


func _play(policy: String, choices: Dictionary) -> Cell:
	var cell := Cell.new()
	cell.policy = policy
	cell.choices = choices
	for a in ACTS:
		cell.acts.append(ActRow.new())
	var variants := CampaignVariants.defaults()
	for decision: String in choices:
		variants.choose(decision, str(choices[decision]))
	for i in runs:
		var autoplay := CampaignAutoplay.new(variants)
		autoplay.policy = policy
		autoplay.grow = grow
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
	lines.append("Expected losses: %d auto-played campaigns per row (seeds %d to %d). Squads grow by PostFight but play SimpleFightPolicy: floors, not promises." % [
		runs, base_seed, base_seed + runs - 1])
	lines.append("%-8s %-28s %4s %8s %6s %7s %8s %11s %10s" % [
		"policy", "switches", "act", "reached", "limit", "fights", "win/fight", "mean losses", "limit hit"])
	for cell in cells:
		for a in cell.acts.size():
			var row := cell.acts[a]
			lines.append("%-8s %-28s %4d %8d %6s %7d %8.0f%% %11.2f %9.0f%%" % [
				cell.policy, set_name(cell.choices), a + 1, row.reached, str(row.limit) if row.reached > 0 else "-",
				row.fights, row.win_percent(), row.mean_losses(), row.limit_hit_percent()])
		lines.append("%-8s %-28s boss: fought %d, won %d; breaches %d" % [
			cell.policy, set_name(cell.choices), cell.boss_fought, cell.boss_won, cell.breaches])
	if not problems.is_empty():
		lines.append("Problems: " + "; ".join(problems))
	return "\n".join(lines)


## The same table as Markdown, for a pull request.
func format_markdown() -> String:
	var lines := PackedStringArray()
	lines.append("| Policy | Switches | Act | Reached | Limit | Win/fight | Mean losses | Limit hit |")
	lines.append("|---|---|---|---|---|---|---|---|")
	for cell in cells:
		for a in cell.acts.size():
			var row := cell.acts[a]
			if row.reached == 0:
				continue
			lines.append("| %s | %s | %d | %d | %d | %.0f%% | %.2f | %.0f%% |" % [
				cell.policy, set_name(cell.choices), a + 1, row.reached, row.limit, row.win_percent(),
				row.mean_losses(), row.limit_hit_percent()])
	return "\n".join(lines)
