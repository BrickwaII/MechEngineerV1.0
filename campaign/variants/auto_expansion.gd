class_name AutoExpansion
extends RefCounted
## The auto-expansion decision: in later acts, held ground slowly spreads into
## weakly defended neighbors on its own. TODO(decision: auto-expansion).
##
## off (the default): nothing spreads.
## simple: a progress meter, no dice, so a run stays deterministic. Once a day
##   (when the day's last point passes), from act from_act on:
##   - A candidate is a hostile region next to a held one, with defense at
##     most max_defense.
##   - Each candidate gains progress_per_day percent per held neighbor; one
##     that is the player's focus, or next to it, gains focus_multiplier times
##     that. The focus is the region the player last attacked or selected
##     (Campaign.set_focus()).
##   - A region no longer a candidate loses its progress.
##   - At 100 percent the region is taken without a fight, as after a capture
##     (pressure.after_capture), at most claims_per_day a day, the furthest
##     along first (file order on a tie).
##   The numbers are this option's params in data/variants/variants.json.
##   Progress and the focus live in RunState, so saves keep them.

const FULL := 100.0


static func is_on(v: CampaignVariants, act: int) -> bool:
	return v.is_chosen(CampaignVariants.AUTO_EXPANSION, CampaignVariants.EXPANSION_SIMPLE) \
		and act + 1 >= v.param_int(CampaignVariants.AUTO_EXPANSION, "from_act", 1)


## The regions that may be claimed now, in file order.
static func candidates(map: RegionMap, state: RunState, v: CampaignVariants) -> PackedStringArray:
	var max_defense := v.param_int(CampaignVariants.AUTO_EXPANSION, "max_defense", 0)
	var out := PackedStringArray()
	for region in map.regions:
		if region.id in state.owned or region.defense > max_defense:
			continue
		if _held_neighbors(region, state) > 0:
			out.append(region.id)
	return out


## Whether `region_id` is the focus or next to it.
static func is_near_focus(map: RegionMap, state: RunState, region_id: String) -> bool:
	if state.focus_id.is_empty() or not map.has_region(state.focus_id):
		return false
	return region_id == state.focus_id or map.get_region(state.focus_id).is_adjacent_to(region_id)


## Progress a candidate gains in a day.
static func daily_gain(map: RegionMap, state: RunState, v: CampaignVariants, region_id: String) -> float:
	var gain := v.param_float(CampaignVariants.AUTO_EXPANSION, "progress_per_day") \
		* _held_neighbors(map.get_region(region_id), state)
	if is_near_focus(map, state, region_id):
		gain *= v.param_float(CampaignVariants.AUTO_EXPANSION, "focus_multiplier", 1.0)
	return gain


## One day of expansion: progress moves in state.expansion, and the ids of the
## regions now due to be claimed are returned, the caller takes them.
static func advance_day(map: RegionMap, state: RunState, v: CampaignVariants) -> PackedStringArray:
	var now := candidates(map, state, v)
	var kept: Dictionary[String, float] = {}
	for region_id in now:
		kept[region_id] = minf(FULL, state.expansion.get(region_id, 0.0) + daily_gain(map, state, v, region_id))
	state.expansion = kept
	var due: Array[String] = []
	for region_id in now:
		if kept[region_id] >= FULL:
			due.append(region_id)
	var order := map.ids()
	due.sort_custom(func(a: String, b: String) -> bool:
		return kept[a] > kept[b] if kept[a] != kept[b] else order.find(a) < order.find(b))
	var out := PackedStringArray()
	for i in mini(due.size(), v.param_int(CampaignVariants.AUTO_EXPANSION, "claims_per_day", 1)):
		out.append(due[i])
		state.expansion.erase(due[i])
	return out


static func _held_neighbors(region: MapRegion, state: RunState) -> int:
	var n := 0
	for other_id in region.adjacent:
		if other_id in state.owned:
			n += 1
	return n
