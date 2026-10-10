class_name BatchReport
extends RefCounted
## Totals over a batch of simulated fights: win rate, fight length and energy.
## Spread is the population standard deviation.

var scenario_name := ""
var base_seed := 0
var records: Array[Dictionary] = []
var problems: Array[String] = []

var runs := 0
var wins := 0
var timeouts := 0
var win_rate := 0.0
var actions := Spread.new()
var ticks := Spread.new()
var squad_energy := Spread.new()
var enemy_energy := Spread.new()
## Unit id -> {name, side, damage: Spread, energy: Spread}.
var per_unit := {}


class Spread:
	var mean := 0.0
	var stddev := 0.0
	var min_value := 0.0
	var max_value := 0.0

	static func of(values: Array[float]) -> Spread:
		var s := Spread.new()
		if values.is_empty():
			return s
		var total := 0.0
		for v in values:
			total += v
		s.mean = total / values.size()
		var squares := 0.0
		for v in values:
			squares += (v - s.mean) * (v - s.mean)
		s.stddev = sqrt(squares / values.size())
		s.min_value = values.min()
		s.max_value = values.max()
		return s

	func text(decimals := 1) -> String:
		var f := "%." + str(decimals) + "f"
		return (f + " ± " + f + "  (min " + f + ", max " + f + ")") % [mean, stddev, min_value, max_value]


static func from_records(p_scenario_name: String, p_base_seed: int, p_records: Array[Dictionary]) -> BatchReport:
	var r := BatchReport.new()
	r.scenario_name = p_scenario_name
	r.base_seed = p_base_seed
	r.records = p_records
	r.runs = p_records.size()
	var acts: Array[float] = []
	var tks: Array[float] = []
	var squad: Array[float] = []
	var enemy: Array[float] = []
	var unit_values := {}
	for rec in p_records:
		if rec.outcome == "victory":
			r.wins += 1
		if rec.timed_out:
			r.timeouts += 1
		acts.append(float(rec.actions))
		tks.append(float(rec.ticks))
		squad.append(float(rec.squad_energy_spent))
		enemy.append(float(rec.enemy_energy_spent))
		for u: Dictionary in rec.units:
			if not unit_values.has(u.id):
				unit_values[u.id] = {"name": u.name, "side": u.side, "damage": [] as Array[float], "energy": [] as Array[float]}
			unit_values[u.id].damage.append(float(u.damage_dealt))
			unit_values[u.id].energy.append(float(u.energy_spent))
	r.win_rate = float(r.wins) / r.runs if r.runs > 0 else 0.0
	r.actions = Spread.of(acts)
	r.ticks = Spread.of(tks)
	r.squad_energy = Spread.of(squad)
	r.enemy_energy = Spread.of(enemy)
	for id: String in unit_values:
		var v: Dictionary = unit_values[id]
		# Units that appear in only some fights (drawn enemies) average over those fights.
		r.per_unit[id] = {"name": v.name, "side": v.side, "fights": v.damage.size(),
			"damage": Spread.of(v.damage), "energy": Spread.of(v.energy)}
	return r


## The report as printed by the command line simulator.
func format_text() -> String:
	var lines := PackedStringArray()
	lines.append("Scenario: %s" % scenario_name)
	if not problems.is_empty():
		lines.append("Cannot run:")
		for p in problems:
			lines.append("  - " + p)
		return "\n".join(lines)
	lines.append("Runs: %d (seeds %d to %d)" % [runs, base_seed, base_seed + runs - 1])
	lines.append("Win rate: %.1f%%  (%d won, %d lost, %d of the losses at the action limit)" % [
		win_rate * 100.0, wins, runs - wins, timeouts])
	lines.append("Fight length, actions: " + actions.text())
	lines.append("Fight length, ticks:   " + ticks.text())
	lines.append("Energy spent, squad:   " + squad_energy.text())
	lines.append("Energy spent, enemies: " + enemy_energy.text())
	lines.append("Per unit (mean ± spread over the fights it was in):")
	var ids := per_unit.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		return [per_unit[a].side != "player", a] < [per_unit[b].side != "player", b])
	for id: String in ids:
		var u: Dictionary = per_unit[id]
		lines.append("  %-6s %-34s fights %4d  damage %s  energy %s" % [
			u.side, "%s (%s)" % [u.name, id], u.fights, (u.damage as Spread).text(), (u.energy as Spread).text()])
	return "\n".join(lines)
