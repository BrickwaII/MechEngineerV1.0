class_name FactionTable
extends RefCounted
## Which enemy faction holds each region, and which of its units a fight
## there fields, loaded from data/combat/factions.json. The enemy-factions
## switch (FightVariants) picks the rule:
##
##   by_act   the faction listed for the region in its act (default)
##   mixed    a faction from mixed_pool per region, fixed by the region id
##   generic  no factions: today's generic roster (enemy_tables.json pools)
##
## Region ids are unique across acts, so a region id alone finds its act.
## A territory outside every act (tests, demos) always gets the generic
## roster. The map reads a region's faction with faction_for_region().

const DEFAULT_PATH := "res://data/combat/factions.json"
## No faction: the generic roster.
const GENERIC := ""

## Faction id -> {name, short_name, color, icon, description, units: [{unit, from_level}]}.
var factions: Dictionary = {}
## Tier names, weakest first.
var tiers: Array[String] = []
## Act id -> tier name per defense level (index 0 to 5).
var tier_by_act: Dictionary = {}
## Factions a region may get under the mixed rule.
var mixed_pool: Array[String] = []
## Act id -> {region id -> faction id}.
var regions_by_act: Dictionary = {}
## Region id -> act id.
var _act_of_region: Dictionary = {}
## Regions listed more than once.
var _duplicates: Array[String] = []

static var _cached_default: FactionTable


## The shipped table. Read once and shared; do not change it.
static func load_default() -> FactionTable:
	if _cached_default == null:
		_cached_default = load_file(DEFAULT_PATH)
	return _cached_default


static func load_file(path: String) -> FactionTable:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("FactionTable: cannot read %s" % path)
		return null
	return from_dict(parsed)


static func from_dict(d: Dictionary) -> FactionTable:
	var t := FactionTable.new()
	t.factions = d.get("factions", {})
	for tier: Variant in d.get("tiers", []):
		t.tiers.append(str(tier))
	t.tier_by_act = d.get("tier_by_act", {})
	for f: Variant in d.get("mixed_pool", []):
		t.mixed_pool.append(str(f))
	var regions: Dictionary = d.get("regions", {})
	for act: String in regions:
		var by_region := {}
		for faction: String in regions[act]:
			for region: String in regions[act][faction]:
				if t._act_of_region.has(region):
					t._duplicates.append(region)
				by_region[region] = faction
				t._act_of_region[region] = act
		t.regions_by_act[act] = by_region
	return t


## The enemy id of `unit` in `tier`: "resistance_soldier_medium".
static func enemy_id(unit: String, tier: String) -> String:
	return "%s_%s" % [unit, tier]


## The act a region belongs to, or "" when no act lists it.
func act_of(region_id: String) -> String:
	return _act_of_region.get(region_id, "")


## The faction holding `region_id` under `rule` (a FightVariants
## enemy-factions option), or GENERIC.
func faction_for_region(region_id: String, rule := FightVariants.FACTIONS_BY_ACT) -> String:
	var act := act_of(region_id)
	if act.is_empty() or rule == FightVariants.FACTIONS_GENERIC:
		return GENERIC
	if rule == FightVariants.FACTIONS_MIXED:
		if mixed_pool.is_empty():
			return GENERIC
		return mixed_pool[posmod(region_id.hash(), mixed_pool.size())]
	return (regions_by_act[act] as Dictionary).get(region_id, GENERIC)


## The faction holding `region_id` in `act_id`, or GENERIC when the act does
## not list it.
func faction_of(act_id: String, region_id: String, rule := FightVariants.FACTIONS_BY_ACT) -> String:
	if act_of(region_id) != act_id:
		return GENERIC
	return faction_for_region(region_id, rule)


func faction_name(faction: String) -> String:
	return str(factions.get(faction, {}).get("name", "Generic"))


## A 32x32 picture of the faction (res:// path), or "" for GENERIC.
func faction_icon(faction: String) -> String:
	return str(factions.get(faction, {}).get("icon", ""))


func faction_color(faction: String) -> Color:
	return Color(str(factions.get(faction, {}).get("color", "#8798ad")))


## The tier enemies field at `level` in `act_id`; the first tier when the act
## or level is unknown.
func tier_for(act_id: String, level: int) -> String:
	var by_level: Array = tier_by_act.get(act_id, [])
	if by_level.is_empty():
		return tiers[0] if not tiers.is_empty() else ""
	return str(by_level[clampi(level, 0, by_level.size() - 1)])


## The enemy ids `faction` can field at `level` in `tier`, in data order.
func pool(faction: String, level: int, tier: String) -> Array[String]:
	var out: Array[String] = []
	for u: Dictionary in factions.get(faction, {}).get("units", []):
		if int(u.get("from_level", 0)) <= level:
			out.append(enemy_id(str(u.unit), tier))
	return out


## Enemy ids for one fight of `faction` at `level` in `tier`. The count comes
## from `table`'s level entry unless `count` is 0 or more; draws use `rng`.
func pick(table: EnemyTable, faction: String, level: int, tier: String, rng: RandomNumberGenerator,
		count := -1) -> Array[String]:
	var ids := pool(faction, level, tier)
	var out: Array[String] = []
	if ids.is_empty():
		return out
	for i in (count if count >= 0 else int(table.levels[level].count)):
		out.append(ids[rng.randi_range(0, ids.size() - 1)])
	return out


## Enemy ids for a fight at `territory_id`, or [] when the territory gets the
## generic roster under `rule`.
func pick_for_territory(table: EnemyTable, territory_id: String, level: int, rule: String,
		rng: RandomNumberGenerator) -> Array[String]:
	var faction := faction_for_region(territory_id, rule)
	if faction == GENERIC:
		return []
	return pick(table, faction, level, tier_for(act_of(territory_id), level), rng)


## Problems in the table checked against `table`; empty when every faction,
## unit type, tier and act entry is usable.
func validate(table: EnemyTable) -> Array[String]:
	var problems: Array[String] = []
	var levels := FightRequest.MAX_DEFENSE_LEVEL - FightRequest.MIN_DEFENSE_LEVEL + 1
	for faction: String in factions:
		var units: Array = factions[faction].get("units", [])
		if pool(faction, FightRequest.MIN_DEFENSE_LEVEL, tiers[0] if not tiers.is_empty() else "").is_empty():
			problems.append("faction %s fields nothing at level %d" % [faction, FightRequest.MIN_DEFENSE_LEVEL])
		for u: Dictionary in units:
			for tier in tiers:
				var id := enemy_id(str(u.unit), tier)
				if not table.enemies.has(id):
					problems.append("faction %s: no enemy %s" % [faction, id])
				elif str(table.enemies[id].get("faction", "")) != faction:
					problems.append("enemy %s is not marked faction %s" % [id, faction])
	for act: String in tier_by_act:
		var by_level: Array = tier_by_act[act]
		if by_level.size() != levels:
			problems.append("act %s: tier_by_act needs %d levels" % [act, levels])
		for tier: Variant in by_level:
			if not str(tier) in tiers:
				problems.append("act %s: unknown tier %s" % [act, tier])
	for act: String in regions_by_act:
		if not tier_by_act.has(act):
			problems.append("act %s has regions but no tier_by_act" % act)
		for region: String in regions_by_act[act]:
			if not factions.has(regions_by_act[act][region]):
				problems.append("region %s: unknown faction %s" % [region, regions_by_act[act][region]])
	for region in _duplicates:
		problems.append("region %s is listed more than once" % region)
	for f in mixed_pool:
		if not factions.has(f):
			problems.append("mixed_pool: unknown faction %s" % f)
	return problems
