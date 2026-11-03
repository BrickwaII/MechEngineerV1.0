class_name BattleRunSummary
extends RefCounted
## A whole Battle Mode run in numbers: built from its BattleFightRecords for
## the end-of-run screen, the sim's printout and runs.csv.

const CSV_HEADER: Array[String] = [
	"run_id", "length", "seed", "squad", "policy", "fights", "won", "cleared", "turns", "avg_turns",
	"hp_lost", "avg_hp_lost_percent", "energy_spent", "energy_wasted", "wasted_percent", "top_action",
	"top_share_percent", "dominated_fights", "action_uses", "combos", "setups", "staggers", "rank_ups",
]

var run_id := ""
var length_id := ""
var run_seed := 0
## The squad's preset id, or "draft".
var squad_label := ""
## The policy that played the squad, or "player".
var policy := ""
var records: Array[BattleFightRecord] = []
## A gauntlet won to its last fight.
var cleared := false
## Fights whose top action took more than this percent of the turns.
var dominant_share_percent := 50


func fights() -> int:
	return records.size()


func won() -> int:
	return records.filter(func(r: BattleFightRecord) -> bool: return r.victory).size()


func total(field: String) -> int:
	var sum := 0
	for r in records:
		sum += int(r.call(field) if r.has_method(field) else r.get(field))
	return sum


func avg_turns() -> float:
	return float(total("turns")) / fights() if fights() > 0 else 0.0


## Mean of each fight's HP lost as a percent of the squad's full HP.
func avg_hp_lost_percent() -> float:
	if records.is_empty():
		return 0.0
	var sum := 0.0
	for r in records:
		sum += 100.0 * r.hp_lost() / maxi(1, r.hp_max)
	return sum / records.size()


func energy_spent() -> float:
	return float(total("energy_spent_milli")) / Combatant.MILLI


func energy_wasted() -> float:
	return float(total("energy_wasted_milli")) / Combatant.MILLI


## Wasted energy as a percent of all the energy the squad recharged or spent.
func wasted_percent() -> int:
	return BattleFightRecord.percent_of(total("energy_wasted_milli"),
		total("energy_wasted_milli") + total("energy_spent_milli"))


## Action id -> squad uses over the whole run.
func action_uses() -> Dictionary:
	var out := {}
	for r in records:
		for id: String in r.action_uses:
			out[id] = int(out.get(id, 0)) + int(r.action_uses[id])
	return out


## [action id, uses, share percent] for every action used, most used first
## (ties alphabetical).
func action_shares() -> Array:
	var uses := action_uses()
	var ids: Array = uses.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		return int(uses[a]) > int(uses[b]) or (int(uses[a]) == int(uses[b]) and a < b))
	var turns := total("turns")
	var out: Array = []
	for id: String in ids:
		out.append([id, int(uses[id]), BattleFightRecord.percent_of(int(uses[id]), turns)])
	return out


func top_action() -> String:
	return BattleFightRecord.top_of(action_uses())


func top_share_percent() -> int:
	return BattleFightRecord.percent_of(int(action_uses().get(top_action(), 0)), total("turns"))


## Fights where one action took more than dominant_share_percent of the turns.
func dominated_fights() -> int:
	return records.filter(func(r: BattleFightRecord) -> bool: return r.is_dominated(dominant_share_percent)).size()


func outcome_text() -> String:
	if cleared:
		return "Cleared all %d fights" % fights()
	if records.is_empty():
		return "No fights"
	if records[-1].victory:
		return "Stopped after fight %d" % records[-1].fight_number
	return "Fell at fight %d (%s)" % [records[-1].fight_number, records[-1].kind]


## The end-of-run summary as text. `names` maps an action id to its name.
func format_text(names: Callable = Callable()) -> String:
	var lines := PackedStringArray()
	lines.append("Battle Mode %s, seed %d, squad %s, played by %s" % [length_id, run_seed, squad_label, policy])
	lines.append("%s: %d of %d fights won" % [outcome_text(), won(), fights()])
	lines.append("Turns %d (%s per fight), HP lost %d (%s%% of the squad per fight)" % [
		total("turns"), TextFormat.short_number(snappedf(avg_turns(), 0.1)), total("hp_lost"),
		TextFormat.short_number(snappedf(avg_hp_lost_percent(), 0.1))])
	lines.append("Energy %s spent, %s wasted (%d%%)" % [
		TextFormat.short_number(energy_spent()), TextFormat.short_number(energy_wasted()), wasted_percent()])
	var shares := PackedStringArray()
	for s: Array in action_shares():
		shares.append("%s %d%%" % [_name(names, s[0]), s[2]])
	lines.append("Action share: %s" % (", ".join(shares) if not shares.is_empty() else "-"))
	lines.append("Fights with one action above %d%%: %d of %d" % [dominant_share_percent, dominated_fights(), fights()])
	lines.append("Combos %d, setups %d, Staggers %d, rank-ups %d" % [
		total("combos"), total("setups"), total("staggers"), total("rank_ups")])
	lines.append("Per fight:")
	for r in records:
		lines.append("  " + r.line(names))
	return "\n".join(lines)


func csv_row() -> Array:
	return [
		run_id, length_id, run_seed, squad_label, policy, fights(), won(), cleared, total("turns"),
		TextFormat.short_number(snappedf(avg_turns(), 0.1)), total("hp_lost"),
		TextFormat.short_number(snappedf(avg_hp_lost_percent(), 0.1)), TextFormat.short_number(energy_spent()),
		TextFormat.short_number(energy_wasted()), wasted_percent(), top_action(), top_share_percent(),
		dominated_fights(), BattleFightRecord.uses_text(action_uses()), total("combos"), total("setups"),
		total("staggers"), total("rank_ups"),
	]


static func _name(names: Callable, id: String) -> String:
	return str(names.call(id)) if names.is_valid() else id
