class_name DifficultyRules
extends RefCounted
## The difficulty curve across a run, by the difficulty-curve switch
## (FightVariants): which enemy tier each act fields at each defense level,
## and how much tougher an act's enemies are. Every rule is deterministic.
##
##   flat   tier_by_act from data/combat/factions.json, enemy stats as listed
##          in data/combat/enemy_tables.json (the old rule)
##   tuned  the option's tier_by_act replaces the factions file's, and every
##          enemy fought in a territory gets the option's scaling: its act's
##          entry in scaling (hp_percent, attack_percent, defense_percent),
##          or, for a territory outside every act (the boss stub), the entry
##          named by the territory id; on top of that, its tier's entry in
##          tier_scaling (the same keys, multiplied). Tuned with tools/balance_sim.gd against
##          data/combat/difficulty_targets.json.
##
## TODO(decision: difficulty-targets): the target bands, the tables and the
## scaling are stand-ins. R2-B's alert tiers raise the tier inside an act on
## top of these tables.


static func tuned(tuning: CombatTuning) -> bool:
	return tuning != null and tuning.variants != null and tuning.variants.is_chosen(
		FightVariants.DIFFICULTY_CURVE, FightVariants.DIFFICULTY_TUNED)


## The tier enemies of `act_id` field at `level`.
static func tier_for(factions: FactionTable, act_id: String, level: int, tuning: CombatTuning) -> String:
	if tuned(tuning):
		var by_level: Variant = _params(tuning).get("tier_by_act", {}).get(act_id, [])
		if by_level is Array and not by_level.is_empty():
			return str(by_level[clampi(level, 0, by_level.size() - 1)])
	return factions.tier_for(act_id, level)


## The scaling key of `territory_id`: its act, or the territory itself when
## no act lists it.
static func scaling_key(factions: FactionTable, territory_id: String) -> String:
	var act := factions.act_of(territory_id) if factions != null else ""
	return act if not act.is_empty() else territory_id


## `stats` of an enemy of `tier` fought under `key`, as the switch has them:
## a scaled copy, or `stats` itself when nothing scales.
static func scaled(stats: UnitStats, key: String, tier: String, tuning: CombatTuning) -> UnitStats:
	if not tuned(tuning):
		return stats
	var by_key: Variant = _params(tuning).get("scaling", {}).get(key, {})
	var by_tier: Variant = _params(tuning).get("tier_scaling", {}).get(tier, {})
	var a: Dictionary = by_key if by_key is Dictionary else {}
	var b: Dictionary = by_tier if by_tier is Dictionary else {}
	if a.is_empty() and b.is_empty():
		return stats
	return UnitStats.new(
		_percent(stats.hp, a, b, "hp_percent"), _percent(stats.attack, a, b, "attack_percent"),
		_percent(stats.defense, a, b, "defense_percent"), stats.speed, stats.elasticity, stats.battery_capacity)


static func _percent(value: int, a: Dictionary, b: Dictionary, key: String) -> int:
	return maxi(0, roundi(value * float(a.get(key, 100)) * float(b.get(key, 100)) / 10000.0))


static func _params(tuning: CombatTuning) -> Dictionary:
	return (tuning.variants.params_by_option.get(FightVariants.DIFFICULTY_CURVE, {}) as Dictionary).get(
		FightVariants.DIFFICULTY_TUNED, {})
