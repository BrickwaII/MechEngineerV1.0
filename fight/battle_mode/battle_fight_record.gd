class_name BattleFightRecord
extends RefCounted
## What one Battle Mode fight measured (BattleFightRecorder): the numbers that
## say whether fights are fun. Played and simulated fights fill it the same
## way, so their numbers compare.

const CSV_HEADER: Array[String] = [
	"run_id", "fight", "kind", "enemies", "types", "victory", "turns", "actions", "ticks",
	"hp_start", "hp_end", "hp_max", "hp_lost", "energy_spent", "energy_wasted", "top_action",
	"top_share_percent", "action_uses", "combos", "setups", "staggers", "enemies_downed",
	"bots_downed", "rank_ups",
]

var fight_number := 0
## BattleEncounter kind name: normal, elite or boss.
var kind := "normal"
var enemy_ids: Array[String] = []
var distinct_types := 0
var victory := false
## Squad decisions (skills and waits).
var turns := 0
## Every decision in the fight, both sides (Fight.action_count).
var actions := 0
var ticks := 0
## Squad HP summed over the bots: at the start, at the end, and full.
var hp_start := 0
var hp_end := 0
var hp_max := 0
var energy_spent_milli := 0
## Recharge lost to full batteries (BattleFightRecorder).
var energy_wasted_milli := 0
## Combat skill id (or "wait") -> squad uses.
var action_uses: Dictionary = {}
## Squad hits that cashed in a setup: a status bonus (Exposed) or a payoff.
var combos := 0
## Setup statuses the squad put on enemies.
var setups := 0
## Enemy Staggers the squad caused (broken plating).
var staggers := 0
var enemies_downed := 0
var bots_downed := 0
## Skill rank-ups after the fight (PostFightReport), set by BattleModeRun.
var rank_ups := 0


func hp_lost() -> int:
	return maxi(0, hp_start - hp_end)


func energy_spent() -> float:
	return float(energy_spent_milli) / Combatant.MILLI


func energy_wasted() -> float:
	return float(energy_wasted_milli) / Combatant.MILLI


## The most-used action id, "" when the squad took no turn. Ties go to the
## id first in alphabetical order, so the answer replays.
func top_action() -> String:
	return BattleFightRecord.top_of(action_uses)


func top_share_percent() -> int:
	return share_percent(top_action())


func share_percent(action_id: String) -> int:
	return BattleFightRecord.percent_of(int(action_uses.get(action_id, 0)), turns)


## True when one action took more than `threshold` percent of the turns.
func is_dominated(threshold: int) -> bool:
	return turns > 0 and top_share_percent() > threshold


## The compact per-fight line for the readout and the logs.
func line(names: Callable = Callable()) -> String:
	var top := top_action()
	var top_name := top if not names.is_valid() or top.is_empty() else str(names.call(top))
	return "Fight %d %s: %s in %d turns, HP -%d, energy %s spent / %s wasted, top %s %d%%, combos %d, staggers %d" % [
		fight_number, kind, "won" if victory else "lost", turns, hp_lost(), TextFormat.short_number(energy_spent()),
		TextFormat.short_number(energy_wasted()), top_name if not top_name.is_empty() else "-", top_share_percent(),
		combos, staggers]


func csv_row(run_id: String) -> Array:
	return [
		run_id, fight_number, kind, " ".join(enemy_ids), distinct_types, victory, turns, actions, ticks,
		hp_start, hp_end, hp_max, hp_lost(), TextFormat.short_number(energy_spent()), TextFormat.short_number(energy_wasted()),
		top_action(), top_share_percent(), BattleFightRecord.uses_text(action_uses), combos, setups, staggers,
		enemies_downed, bots_downed, rank_ups,
	]


## Most-used key of an id -> count map; ties go to the first id alphabetically.
static func top_of(uses: Dictionary) -> String:
	var ids: Array = uses.keys()
	ids.sort()
	var best := ""
	for id: String in ids:
		if best.is_empty() or int(uses[id]) > int(uses[best]):
			best = id
	return best


static func percent_of(part: int, whole: int) -> int:
	return roundi(100.0 * part / whole) if whole > 0 else 0


## "heavy_strike=2 strike=5", ids in alphabetical order.
static func uses_text(uses: Dictionary) -> String:
	var ids: Array = uses.keys()
	ids.sort()
	var parts := PackedStringArray()
	for id: String in ids:
		parts.append("%s=%d" % [id, int(uses[id])])
	return " ".join(parts)
