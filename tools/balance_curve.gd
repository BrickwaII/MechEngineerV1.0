class_name BalanceCurve
extends RefCounted
## The balance sim: plays seeded auto-fights of freshly drafted squads against
## each act's early and late enemies and the boss, and checks every win rate
## against its target band in data/combat/difficulty_targets.json.
##
##   var curve := BalanceCurve.run()                       # the data file's cases
##   var old := BalanceCurve.run(-1, 1, {"speed-range": "wide"})
##   print(curve.format_text())
##
## Run i of every case drafts a squad from seed base_seed + i (BotFactory, the
## default draft) and fights enemies drawn with that seed, so every case and
## every variant set meets the same squads. A case's enemies are one of its
## act's factions at the act's tier for the defense level, raised tier_steps
## tiers (late-act alert); a case with no factions fights the generic roster
## (the boss stub). skill_ranks_added stands in for a squad's growth by then.
## The fight is fought over the case's territory (default: its act id), which
## picks the difficulty-curve scaling.
## `choices` (decision id -> option id) override fight switches, so the old
## behaviour can be measured next to the new; every other switch stays at its
## default.

const DEFAULT_PATH := "res://data/combat/difficulty_targets.json"


## An enemy table that fields one faction at one tier, whatever the territory.
class ForcedTierTable:
	extends EnemyTable
	var forced: FactionTable
	var faction := ""
	var tier := ""

	func pick(level: int, rng: RandomNumberGenerator) -> Array[String]:
		return forced.pick(self, faction, level, tier, rng)


## One target from the data file.
class Case:
	var id := ""
	var factions: Array[String] = []
	var act := ""
	## The territory the fight is fought over: picks the difficulty-curve
	## scaling (DifficultyRules). Defaults to the act.
	var territory := ""
	var defense_level := 0
	var tier_steps := 0
	var skill_ranks_added := 0
	var target_low := 0.0
	var target_high := 100.0


## One case's outcome.
class CaseResult:
	var case: Case
	## The tier fought, or "" for the generic roster.
	var tier := ""
	var wins := 0
	var runs := 0

	func win_rate() -> float:
		return 100.0 * wins / runs if runs > 0 else 0.0

	## "ok", "low" (too hard) or "high" (too easy).
	func verdict() -> String:
		if win_rate() < case.target_low:
			return "low"
		if win_rate() > case.target_high:
			return "high"
		return "ok"


var runs := 0
var base_seed := 0
var player_policy := ""
var enemy_policy := ""
var choices := {}
var cases: Array[Case] = []
var results: Array[CaseResult] = []
var problems: Array[String] = []


## Plays every case. `p_runs` < 1 uses the data file's runs.
static func run(p_runs := -1, p_base_seed := 1, p_choices := {}, path := DEFAULT_PATH) -> BalanceCurve:
	var curve := BalanceCurve.new()
	curve.base_seed = p_base_seed
	curve.choices = p_choices
	var data := _read(path)
	if data.is_empty():
		curve.problems.append("cannot read %s" % path)
		return curve
	curve.runs = p_runs if p_runs > 0 else int(data.get("runs", 100))
	curve.player_policy = str(data.get("squad_policy", "patient"))
	curve.enemy_policy = str(data.get("enemy_policy", "intent"))
	curve.cases = parse_cases(data, curve.problems)
	FightScenario.make_policy(curve.player_policy, curve.problems)
	FightScenario.make_policy(curve.enemy_policy, curve.problems)
	var variants := FightVariants.defaults()
	for decision: String in p_choices:
		if not variants.choose(decision, str(p_choices[decision])):
			curve.problems.append("unknown fight option %s=%s" % [decision, p_choices[decision]])
	var base := EnemyTable.load_default()
	FactionWinRates.problems_into(base, curve.problems)
	if not curve.problems.is_empty():
		return curve
	var tuning := CombatTuning.load_default().with_variants(variants)
	for c in curve.cases:
		curve.results.append(curve._play(c, base, tuning))
	return curve


static func parse_cases(data: Dictionary, out_problems: Array[String]) -> Array[Case]:
	var out: Array[Case] = []
	for entry: Variant in data.get("cases", []):
		if not entry is Dictionary:
			out_problems.append("a case is not an object")
			continue
		var c := Case.new()
		c.id = str(entry.get("id", ""))
		for f: Variant in entry.get("factions", []):
			c.factions.append(str(f))
		c.act = str(entry.get("act", ""))
		c.territory = str(entry.get("territory", c.act))
		c.defense_level = int(entry.get("defense_level", 0))
		c.tier_steps = int(entry.get("tier_steps", 0))
		c.skill_ranks_added = int(entry.get("skill_ranks_added", 0))
		var target: Array = entry.get("target", [0, 100])
		c.target_low = float(target[0]) if target.size() > 0 else 0.0
		c.target_high = float(target[1]) if target.size() > 1 else 100.0
		if c.defense_level < FightRequest.MIN_DEFENSE_LEVEL or c.defense_level > FightRequest.MAX_DEFENSE_LEVEL:
			out_problems.append("case %s: defense_level %d is out of range" % [c.id, c.defense_level])
		if c.target_low > c.target_high:
			out_problems.append("case %s: target low is above high" % c.id)
		out.append(c)
	if out.is_empty():
		out_problems.append("no cases")
	return out


## The tier `c` fights in `factions`: the act's tier (by the difficulty-curve
## switch of `tuning`) raised tier_steps, capped.
static func tier_of(c: Case, factions: FactionTable, tuning: CombatTuning) -> String:
	if c.factions.is_empty() or factions.tiers.is_empty():
		return ""
	var i := factions.tiers.find(DifficultyRules.tier_for(factions, c.act, c.defense_level, tuning))
	return factions.tiers[clampi(maxi(i, 0) + c.tier_steps, 0, factions.tiers.size() - 1)]


func _play(c: Case, base: EnemyTable, tuning: CombatTuning) -> CaseResult:
	var r := CaseResult.new()
	r.case = c
	r.runs = runs
	r.tier = tier_of(c, base.factions, tuning)
	var tables: Array[EnemyTable] = []
	if c.factions.is_empty():
		var generic := EnemyTable.new()
		generic.enemies = base.enemies
		generic.levels = base.levels
		tables.append(generic)
	for faction in c.factions:
		var t := ForcedTierTable.new()
		t.enemies = base.enemies
		t.levels = base.levels
		t.forced = base.factions
		t.faction = faction
		t.tier = r.tier
		tables.append(t)
	var factory := BotFactory.new(BotTuning.load_default())
	var top_rank := tuning.skill_ranks.max_rank() if tuning.skill_ranks != null else Skill.MIN_LEVEL + c.skill_ranks_added
	var unused: Array[String] = []
	for i in runs:
		var run_seed := base_seed + i
		var squad: Array[SquadMemberSummary] = []
		for bot in factory.build_squad(run_seed).get_fielded():
			for skill in bot.skills:
				if skill != null:
					skill.level = clampi(skill.level + c.skill_ranks_added, Skill.MIN_LEVEL, top_rank)
			squad.append(bot.to_summary())
		var request := FightRequest.new(FightRequest.Kind.ATTACK, c.territory, c.defense_level, squad)
		var sim := SimulatedFight.new(request, run_seed,
			FightScenario.make_policy(player_policy, unused), FightScenario.make_policy(enemy_policy, unused),
			tuning, tables[i % tables.size()]).run_to_end()
		if sim.fight.outcome == FightResult.Outcome.VICTORY:
			r.wins += 1
	return r


## Cases on target, out of all.
func on_target() -> int:
	return results.filter(func(r: CaseResult) -> bool: return r.verdict() == "ok").size()


func format_text() -> String:
	var lines := PackedStringArray()
	if not problems.is_empty():
		lines.append("Cannot run the balance sim:")
		for p in problems:
			lines.append("  - " + p)
		return "\n".join(lines)
	lines.append("Balance sim: %d runs per case (seeds %d to %d), squad policy %s, enemy policy %s%s." % [
		runs, base_seed, base_seed + runs - 1, player_policy, enemy_policy,
		(", switches " + _choices_text()) if not choices.is_empty() else ""])
	lines.append("%-12s %6s %-9s %6s %9s %8s %7s" % ["case", "level", "tier", "ranks", "target", "win", "verdict"])
	for r in results:
		lines.append("%-12s %6d %-9s %6d %4.0f-%-4.0f %7.1f%% %7s" % [
			r.case.id, r.case.defense_level, r.tier if not r.tier.is_empty() else "generic",
			r.case.skill_ranks_added, r.case.target_low, r.case.target_high, r.win_rate(), r.verdict()])
	lines.append("%d of %d cases on target." % [on_target(), results.size()])
	return "\n".join(lines)


## The same table as Markdown, for a pull request.
func format_markdown() -> String:
	var lines := PackedStringArray()
	lines.append("| Case | Level | Tier | Target | Win |")
	lines.append("|---|---|---|---|---|")
	for r in results:
		lines.append("| %s | L%d | %s | %.0f-%.0f%% | %.0f%% %s |" % [
			r.case.id, r.case.defense_level, r.tier if not r.tier.is_empty() else "generic",
			r.case.target_low, r.case.target_high, r.win_rate(), "" if r.verdict() == "ok" else "(%s)" % r.verdict()])
	return "\n".join(lines)


func _choices_text() -> String:
	var parts := PackedStringArray()
	for d: String in choices:
		parts.append("%s=%s" % [d, choices[d]])
	return ", ".join(parts)


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
