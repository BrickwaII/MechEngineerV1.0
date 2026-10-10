class_name FactionWinRates
extends RefCounted
## Seeded batch check for the enemy factions: win rates at every defense level
## for each faction in each act's tiers, next to the generic roster (today's
## enemies), so a roster change can be checked against today's rates.
##
##   var rates := FactionWinRates.run(100, 1)
##   print(rates.format_text())
##
## Run i drafts a fresh squad from seed base_seed + i (BotFactory, the default
## draft) and fights enemies drawn with that seed, so every row meets the same
## squads. The squad and enemy policies are the variant comparison's
## (data/scenarios/_dev_tools.json). Every switch stays at its default.

## Row id of the generic roster.
const GENERIC_ROW := "generic"


## Enemy table that fields one faction at one act's tiers, whatever the
## territory.
class ForcedFactionTable:
	extends EnemyTable
	var forced: FactionTable
	var faction := ""
	var act := ""

	func pick(level: int, rng: RandomNumberGenerator) -> Array[String]:
		return forced.pick(self, faction, level, forced.tier_for(act, level), rng)


## One row: a faction in one act (or the generic roster).
class Row:
	var id := ""
	var faction := ""
	var act := ""
	## Defense level -> tier fought ("" for generic).
	var tiers: Array[String] = []
	## Defense level -> wins out of runs.
	var wins: Array[int] = []


var runs := 0
var base_seed := 0
var player_policy := ""
var enemy_policy := ""
var rows: Array[Row] = []
var problems: Array[String] = []


static func run(p_runs: int, p_base_seed: int, levels: Array[int] = []) -> FactionWinRates:
	var r := FactionWinRates.new()
	var settings := DevToolSettings.load_default()
	r.runs = p_runs
	r.base_seed = p_base_seed
	r.player_policy = settings.compare_player_policy
	r.enemy_policy = settings.compare_enemy_policy
	if levels.is_empty():
		for level in range(FightRequest.MIN_DEFENSE_LEVEL, FightRequest.MAX_DEFENSE_LEVEL + 1):
			levels.append(level)
	var base := EnemyTable.load_default()
	var factions := base.factions
	problems_into(base, r.problems)
	if not r.problems.is_empty():
		return r
	var generic := EnemyTable.new()
	generic.enemies = base.enemies
	generic.levels = base.levels
	r.rows.append(r._play(GENERIC_ROW, "", "", generic, factions, levels))
	for faction: String in factions.factions:
		for act: String in factions.tier_by_act:
			var t := ForcedFactionTable.new()
			t.enemies = base.enemies
			t.levels = base.levels
			t.forced = factions
			t.faction = faction
			t.act = act
			r.rows.append(r._play("%s/%s" % [faction, act], faction, act, t, factions, levels))
	return r


static func problems_into(base: EnemyTable, out: Array[String]) -> void:
	if base == null or base.factions == null:
		out.append("cannot read the enemy or faction tables")
		return
	out.append_array(base.validate(CombatTuning.load_default()))


func _play(id: String, faction: String, act: String, table: EnemyTable, factions: FactionTable,
		levels: Array[int]) -> Row:
	var row := Row.new()
	row.id = id
	row.faction = faction
	row.act = act
	var factory := BotFactory.new(BotTuning.load_default())
	var tuning := CombatTuning.load_default()
	var unused: Array[String] = []
	for level in levels:
		row.tiers.append(factions.tier_for(act, level) if not faction.is_empty() else "")
		var wins := 0
		for i in runs:
			var run_seed := base_seed + i
			var squad: Array[SquadMemberSummary] = []
			for bot in factory.build_squad(run_seed).get_fielded():
				squad.append(bot.to_summary())
			var request := FightRequest.new(FightRequest.Kind.ATTACK, "faction_check", level, squad)
			var sim := SimulatedFight.new(request, run_seed,
				FightScenario.make_policy(player_policy, unused), FightScenario.make_policy(enemy_policy, unused),
				tuning, table).run_to_end()
			if sim.fight.outcome == FightResult.Outcome.VICTORY:
				wins += 1
		row.wins.append(wins)
	return row


## Win rate of `row` at level index `i`, in percent.
func rate(row: Row, i: int) -> float:
	return 100.0 * row.wins[i] / runs if runs > 0 else 0.0


func format_text() -> String:
	var lines := PackedStringArray()
	if not problems.is_empty():
		lines.append("Cannot check factions:")
		for p in problems:
			lines.append("  - " + p)
		return "\n".join(lines)
	lines.append("Faction win rates: %d runs per cell (seeds %d to %d), squad policy %s, enemy policy %s." % [
		runs, base_seed, base_seed + runs - 1, player_policy, enemy_policy])
	lines.append("Each run drafts a fresh squad from its seed. Cells: win %, tier (b/m/a). generic = today's enemies.")
	var header := "%-26s" % "faction/act"
	for level in rows[0].wins.size():
		header += " %9s" % ("level %d" % level)
	lines.append(header)
	for row in rows:
		var line := "%-26s" % row.id
		for i in row.wins.size():
			var tier := row.tiers[i].substr(0, 1) if not row.tiers[i].is_empty() else "-"
			line += " %7.0f%% %s" % [rate(row, i), tier]
		lines.append(line)
	return "\n".join(lines)


## The same table as Markdown, for a pull request.
func format_markdown() -> String:
	var lines := PackedStringArray()
	var header := "| Faction / act |"
	var rule := "|---|"
	for level in rows[0].wins.size():
		header += " L%d |" % level
		rule += "---|"
	lines.append(header)
	lines.append(rule)
	for row in rows:
		var line := "| %s |" % row.id
		for i in row.wins.size():
			line += " %.0f%%%s |" % [rate(row, i), (" " + row.tiers[i]) if not row.tiers[i].is_empty() else ""]
		lines.append(line)
	return "\n".join(lines)
