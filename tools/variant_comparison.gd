class_name VariantComparison
extends RefCounted
## Plays the same seeded fights under every option of one switchboard
## decision and totals each option, so the options can be read side by side:
## win rate, fight length and energy use (plus personality drift and HP when
## the decision acts after a fight).
##
##   var cmp := VariantComparison.run("d-wait", 200, 1)
##   print(cmp.format_text())
##
## The squad plays PatientFightPolicy by default (it waits, so the wait
## options differ) and the enemies IntentFightPolicy, as on the battle screen.
## Run i drafts a fresh squad from seed base_seed + i (BotFactory, with the
## draft rule under test for draft-rule) and fights enemies drawn with that
## seed, so every option meets the same squads and enemies. Decisions that act
## between fights (hp-carryover) play `chain_fights` fights in a row per run,
## stopping at the first defeat. Everything else plays one fight per run.
## Every other switch stays at its default.

## Decisions this tool can compare.
const FIGHT_DECISIONS: Array[String] = [
	FightVariants.WAIT_FORM, FightVariants.WAIT_LENGTH, FightVariants.ELASTICITY,
	FightVariants.PERSONALITY_MAP, FightVariants.HP_CARRYOVER,
]
const DRAFT_RULE := "draft-rule"
## Fight k of run i plays seed (base_seed + i) * CHAIN_SEED_STRIDE + k, so
## chained fights never repeat a seed. A seed layout, not a tunable.
const CHAIN_SEED_STRIDE := 1000

## One option's totals.
class OptionResult:
	var option := ""
	var is_default := false
	## Every fight played, as a BatchReport.
	var report: BatchReport
	## Runs that won every fight they played.
	var full_runs := 0
	## Personality change per bot per fight, summed over the scales.
	var drift_per_bot := 0.0
	## Squad hp at the end of each run, in percent of max (0 when wiped).
	var end_hp_percent := 0.0


var decision := ""
var runs := 0
var base_seed := 0
var defense_level := 0
var player_policy := ""
var enemy_policy := ""
var chain_fights := 1
var results: Array[OptionResult] = []
var problems: Array[String] = []


## Compares every option of `decision`. Leave the optional arguments at their
## defaults to use data/scenarios/_dev_tools.json.
static func run(
	p_decision: String,
	p_runs: int,
	p_base_seed: int,
	p_defense_level := -1,
	p_player_policy := "",
	p_enemy_policy := "",
	p_chain_fights := -1,
) -> VariantComparison:
	var settings := DevToolSettings.load_default()
	var cmp := VariantComparison.new()
	cmp.decision = p_decision
	cmp.runs = maxi(0, p_runs)
	cmp.base_seed = p_base_seed
	cmp.defense_level = p_defense_level if p_defense_level >= 0 else settings.compare_defense_level
	cmp.player_policy = p_player_policy if not p_player_policy.is_empty() else settings.compare_player_policy
	cmp.enemy_policy = p_enemy_policy if not p_enemy_policy.is_empty() else settings.compare_enemy_policy
	var chain := p_chain_fights if p_chain_fights > 0 else settings.compare_chain_fights
	cmp.chain_fights = chain if p_decision == FightVariants.HP_CARRYOVER else 1
	FightScenario.make_policy(cmp.player_policy, cmp.problems)
	FightScenario.make_policy(cmp.enemy_policy, cmp.problems)
	var options := cmp.options_of(p_decision)
	if options.is_empty():
		cmp.problems.append("unknown decision '%s' (use %s)" % [p_decision, ", ".join(comparable())])
	if not cmp.problems.is_empty():
		return cmp
	for option: String in options:
		cmp.results.append(cmp._play_option(option))
	return cmp


## Every decision this tool can compare.
static func comparable() -> Array[String]:
	var out: Array[String] = FIGHT_DECISIONS.duplicate()
	out.append(DRAFT_RULE)
	return out


## The options of `p_decision`, the default first; empty if it is unknown.
func options_of(p_decision: String) -> Array[String]:
	var out: Array[String] = []
	if p_decision == DRAFT_RULE:
		var def := BotTuning.load_default().draft_rule
		out.append(def)
		for rule in BotTuning.DRAFT_RULES:
			if rule != def:
				out.append(rule)
		return out
	var v := FightVariants.defaults()
	if not p_decision in FIGHT_DECISIONS:
		return out
	out.append(v.option(p_decision))
	for option: String in (v.params_by_option[p_decision] as Dictionary):
		if not option in out:
			out.append(option)
	return out


func _play_option(option: String) -> OptionResult:
	var r := OptionResult.new()
	r.option = option
	var bot_tuning := BotTuning.load_default()
	var variants := FightVariants.defaults()
	if decision == DRAFT_RULE:
		r.is_default = option == bot_tuning.draft_rule
		bot_tuning.draft_rule = option
	else:
		r.is_default = option == variants.option(decision)
		variants.choose(decision, option)
	var combat_tuning := CombatTuning.load_default().with_variants(variants)
	var post_tuning := PostFightTuning.for_variants(variants)
	var enemy_table := EnemyTable.load_default()
	var factory := BotFactory.new(bot_tuning)
	var records: Array[Dictionary] = []
	var drift_total := 0.0
	var bot_fights := 0
	var hp_percent_total := 0.0
	for i in runs:
		var run_seed := base_seed + i
		var bots := factory.build_squad(run_seed).get_fielded()
		var won_all := true
		for k in chain_fights:
			var squad: Array[SquadMemberSummary] = []
			for bot in bots:
				squad.append(bot.to_summary())
			var request := FightRequest.new(FightRequest.Kind.ATTACK, "compare", defense_level, squad)
			var fight_seed := run_seed * CHAIN_SEED_STRIDE + k if chain_fights > 1 else run_seed
			var problems_unused: Array[String] = []
			var sim := SimulatedFight.new(request, fight_seed,
				FightScenario.make_policy(player_policy, problems_unused), FightScenario.make_policy(enemy_policy, problems_unused),
				combat_tuning, enemy_table).run_to_end()
			records.append(sim.record("%s=%s" % [decision, option]))
			var before := {}
			for bot in bots:
				before[bot.id] = PersonalityDrift.values_of(bot.personality)
			PostFight.apply(sim.fight, bots, null, post_tuning)
			for bot in bots:
				var after := PersonalityDrift.values_of(bot.personality)
				for s in after.size():
					drift_total += absf(after[s] - before[bot.id][s])
				bot_fights += 1
			var end_hp := HpCarryover.end_hp_by_id(sim.fight)
			for bot in bots:
				bot.hp = HpCarryover.hp_after(end_hp.get(bot.id, bot.hp), bot.get_max_hp(), variants)
			if sim.fight.outcome != FightResult.Outcome.VICTORY:
				won_all = false
				break
			if k == chain_fights - 1:
				hp_percent_total += _hp_percent(end_hp, bots)
		if won_all:
			r.full_runs += 1
	r.report = BatchReport.from_records("%s=%s" % [decision, option], base_seed, records)
	r.drift_per_bot = drift_total / bot_fights if bot_fights > 0 else 0.0
	r.end_hp_percent = hp_percent_total / runs if runs > 0 else 0.0
	return r


static func _hp_percent(end_hp: Dictionary[String, int], bots: Array[Bot]) -> float:
	var hp := 0
	var max_hp := 0
	for bot in bots:
		hp += end_hp.get(bot.id, 0)
		max_hp += bot.get_max_hp()
	return 100.0 * hp / max_hp if max_hp > 0 else 0.0


## The side-by-side table the command line prints.
func format_text() -> String:
	var lines := PackedStringArray()
	if not problems.is_empty():
		lines.append("Cannot compare %s:" % decision)
		for p in problems:
			lines.append("  - " + p)
		return "\n".join(lines)
	lines.append("Decision: %s, %d runs per option (seeds %d to %d), defense level %d, squad policy %s, enemy policy %s" % [
		decision, runs, base_seed, base_seed + runs - 1, defense_level, player_policy, enemy_policy])
	lines.append("Each run drafts a fresh squad from its seed; enemies are drawn with the same seed. * marks the default.")
	if chain_fights > 1:
		lines.append("Each run plays up to %d fights in a row with the same squad, stopping at the first defeat." % chain_fights)
	var header := "%-22s %8s %16s %18s %18s %18s %10s" % [
		"option", "win rate", "actions", "ticks", "squad energy", "enemy energy", "drift/bot"]
	if chain_fights > 1:
		header += " %10s %10s" % ["full runs", "end hp%"]
	lines.append(header)
	for r in results:
		var b := r.report
		var line := "%-22s %7.1f%% %16s %18s %18s %18s %10.3f" % [
			r.option + ("*" if r.is_default else ""), b.win_rate * 100.0,
			b.actions.short_text(), b.ticks.short_text(), b.squad_energy.short_text(), b.enemy_energy.short_text(),
			r.drift_per_bot]
		if chain_fights > 1:
			line += " %9.1f%% %9.1f%%" % [100.0 * r.full_runs / maxi(1, runs), r.end_hp_percent]
		lines.append(line)
	lines.append("(mean ± spread over every fight played; fights per option: %s)" % ", ".join(
		results.map(func(r: OptionResult) -> String: return str(r.report.runs))))
	return "\n".join(lines)
