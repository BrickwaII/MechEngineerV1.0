class_name Escalation
extends RefCounted
## Escalation (R2-B): the world notices the player. Each act has three alert
## tiers. Holding enough of the act's map raises the alert one tier for every
## hostile region, so fights get harder as the player wins. Tiers never drop.
## From fortify.from_tier on, hostile regions left alone dig in a level at a
## time. Numbers, tier names and headlines: data/tuning/escalation.json.
##
## The alert tier reaches the fight as the defense level: level_of() moves a
## region's defense into its tier's band, and the faction tables turn levels
## into enemy unit tiers (data/combat/factions.json tier_by_act).
## TODO(decision: escalation-enemy-tier): the tier travels as a defense level,
## not as a FightRequest field of its own, so fights need no contract change.
##
## State lives in RunState.escalation, so saves keep it:
##   tier     the act's alert tier, 0 to 2
##   fortify  hostile region id -> fortification levels
##   quiet    hostile region id -> days left alone since its last level
## The escalation variant (CampaignVariants.ESCALATION) turns it off, or gives
## other thresholds.

## A news card: {kind, tier, tier_name, region, headline, body}. kind is
## NEWS_TIER or NEWS_FORTIFIED; region is "" for a tier change.
signal news(card: Dictionary)

const DEFAULT_PATH := "res://data/tuning/escalation.json"
const NEWS_TIER := "tier"
const NEWS_FORTIFIED := "fortified"

static var _cached: Dictionary = {}

var map: RegionMap
var state: RunState
## False under the escalation variant "off": every region fights at its own
## defense, nothing fortifies and no news comes.
var on := true
## [held, of] pairs: holding held/of of the map raises the alert to tier i + 1.
var thresholds: Array = []
var data: Dictionary


func _init(p_map: RegionMap, p_state: RunState, v: CampaignVariants = null, p_data: Dictionary = {}) -> void:
	map = p_map
	state = p_state
	data = p_data if not p_data.is_empty() else load_data()
	thresholds = data.get("thresholds", [])
	if v != null:
		on = not v.is_chosen(CampaignVariants.ESCALATION, CampaignVariants.ESCALATION_OFF)
		var own: Variant = v.params(CampaignVariants.ESCALATION).get("thresholds")
		if own is Array and not (own as Array).is_empty():
			thresholds = own
	for key in ["fortify", "quiet"]:
		if not state.escalation.get(key) is Dictionary:
			state.escalation[key] = {}
	if not state.escalation.has("tier"):
		state.escalation["tier"] = 0


## data/tuning/escalation.json, read once.
static func load_data() -> Dictionary:
	if _cached.is_empty():
		_cached = JsonFile.read_dict(DEFAULT_PATH)
	return _cached


# --- Alert tier ---------------------------------------------------------------

func tier() -> int:
	return int(state.escalation.get("tier", 0))


func tier_count() -> int:
	return _tiers().size()


func tier_name(t := -1) -> String:
	var tiers := _tiers()
	if tiers.is_empty():
		return ""
	return str(tiers[clampi(t if t >= 0 else tier(), 0, tiers.size() - 1)].get("name", ""))


## "Local", "National" or "Global": the act's scope.
func scope() -> String:
	return str(_act().get("scope", ""))


## Held regions needed to reach tier `t`; 0 for tier 0, -1 past the last.
func needed_for(t: int) -> int:
	if t <= 0:
		return 0
	if t > thresholds.size() or t >= tier_count():
		return -1
	var entry: Dictionary = thresholds[t - 1]
	var of := maxi(1, int(entry.get("of", 1)))
	return (map.regions.size() * int(entry.get("held", 1)) + of - 1) / of


## The tier holding `held` regions earns, before the no-drop rule.
func tier_for_held(held: int) -> int:
	var t := 0
	while needed_for(t + 1) >= 0 and held >= needed_for(t + 1):
		t += 1
	return t


## How far the held count is from the current tier toward the next, 0 to 1;
## 1 at the last tier.
func progress() -> float:
	var next := needed_for(tier() + 1)
	if next < 0:
		return 1.0
	var from := needed_for(tier())
	return clampf(float(state.owned.size() - from) / maxi(1, next - from), 0.0, 1.0)


## Held regions still needed for the next tier, or -1 at the last.
func to_next() -> int:
	var next := needed_for(tier() + 1)
	return maxi(0, next - state.owned.size()) if next >= 0 else -1


## Raises the tier to what the held count earns; never lowers it. Emits a
## news card per tier gained when `announce`. Returns the tiers gained.
func update(announce := true) -> int:
	if not on:
		return 0
	var from := tier()
	var to := maxi(from, tier_for_held(state.owned.size()))
	state.escalation["tier"] = to
	if announce:
		for t in range(from + 1, to + 1):
			news.emit(_tier_card(t))
	return to - from


# --- Enemy level --------------------------------------------------------------

## The defense level `region` fights at: its own defense moved into its alert
## tier's band, plus its fortification, within FightRequest's levels.
func level_of(region: MapRegion) -> int:
	if not on:
		return region.defense
	return clampi(band_level(region.defense, tier()) + fortify_of(region.id),
		FightRequest.MIN_DEFENSE_LEVEL, FightRequest.MAX_DEFENSE_LEVEL)


## A region of `defense` at alert tier `t`, before fortification.
func band_level(defense: int, t: int) -> int:
	return _band(data, state.act, defense, t)


## The mapping from alert tier to fight level, for tools such as a balance
## sim: the defense level a region of `defense` fights at in act `act` (0 for
## act 1) at alert tier `alert`, with `fortify` levels, from the shipped data.
## Equal to level_of() with escalation on.
static func level_for(act: int, defense: int, alert: int, fortify := 0) -> int:
	return clampi(_band(load_data(), act, defense, alert) + fortify,
		FightRequest.MIN_DEFENSE_LEVEL, FightRequest.MAX_DEFENSE_LEVEL)


static func _band(p_data: Dictionary, act: int, defense: int, t: int) -> int:
	var acts: Array = p_data.get("acts", [])
	if acts.is_empty():
		return defense
	var tiers: Array = (acts[clampi(act, 0, acts.size() - 1)] as Dictionary).get("tiers", [])
	if tiers.is_empty():
		return defense
	var band: Dictionary = tiers[clampi(t, 0, tiers.size() - 1)]
	return clampi(defense + int(band.get("level_offset", 0)),
		int(band.get("min_level", FightRequest.MIN_DEFENSE_LEVEL)),
		int(band.get("max_level", FightRequest.MAX_DEFENSE_LEVEL)))


# --- Fortifying ---------------------------------------------------------------

func fortify_of(region_id: String) -> int:
	return int((state.escalation["fortify"] as Dictionary).get(region_id, 0))


func max_fortify() -> int:
	return int(_fortify().get("max_levels", 0))


## Days the region has been left alone toward its next level.
func quiet_days(region_id: String) -> int:
	return int((state.escalation["quiet"] as Dictionary).get(region_id, 0))


func is_fortifying() -> bool:
	return on and tier() >= int(_fortify().get("from_tier", 1))


## One day passes: every hostile region left alone counts a day, and gains a
## level each days_per_level days up to max_levels. One news card names the
## regions that reached max_levels today, if any.
func advance_day() -> void:
	if not is_fortifying():
		return
	var per_level := maxi(1, int(_fortify().get("days_per_level", 1)))
	var fortify: Dictionary = state.escalation["fortify"]
	var quiet: Dictionary = state.escalation["quiet"]
	var capped: Array[String] = []
	for region in map.regions:
		if region.id in state.owned or fortify_of(region.id) >= max_fortify():
			continue
		quiet[region.id] = quiet_days(region.id) + 1
		if quiet[region.id] >= per_level:
			quiet.erase(region.id)
			fortify[region.id] = fortify_of(region.id) + 1
			if fortify[region.id] >= max_fortify():
				capped.append(region.id)
	if not capped.is_empty():
		news.emit(_fortified_card(capped))


## The player attacked `region_id`: its count of days left alone restarts.
func note_attack(region_id: String) -> void:
	(state.escalation["quiet"] as Dictionary).erase(region_id)


## Ownership changed: a captured region loses its fortification and the alert
## may rise. A lost region starts unfortified at the current tier.
func ownership_changed(region_id: String, held: bool) -> void:
	(state.escalation["fortify"] as Dictionary).erase(region_id)
	(state.escalation["quiet"] as Dictionary).erase(region_id)
	if held:
		update()


# --- News ---------------------------------------------------------------------

func _tier_card(t: int) -> Dictionary:
	var news_data: Dictionary = data.get("news", {})
	var by_act: Array = news_data.get("tiers", [])
	var lines: Array = []
	if not by_act.is_empty():
		var act_lines: Array = by_act[clampi(state.act, 0, by_act.size() - 1)]
		if t < act_lines.size():
			lines = act_lines[t]
	return {
		"kind": NEWS_TIER, "tier": t, "tier_name": tier_name(t), "region": "",
		"headline": _fill(_pick(lines), "", 0, t),
		"body": _fill(str(news_data.get("tier_body", "")), "", 0, t),
	}


func _fortified_card(region_ids: Array[String]) -> Dictionary:
	var news_data: Dictionary = data.get("news", {})
	var region_id := region_ids[0]
	return {
		"kind": NEWS_FORTIFIED, "tier": tier(), "tier_name": tier_name(), "region": region_id,
		"regions": region_ids,
		"headline": _fill(_pick(news_data.get("fortified", [])), region_id, max_fortify(), tier()),
		"body": _fill(str(news_data.get("fortified_body", "")), region_id, max_fortify(), tier()),
	}


## A headline picked by the time, so a run is deterministic: the next one
## every news.points_per_headline time points.
func _pick(lines: Array) -> String:
	if lines.is_empty():
		return ""
	var every := maxi(1, int((data.get("news", {}) as Dictionary).get("points_per_headline", 4)))
	return str(lines[(state.time_points / every + tier()) % lines.size()])


func _fill(text: String, region_id: String, count: int, t: int) -> String:
	var region_name := map.get_region(region_id).name if map.has_region(region_id) else ""
	return text.format({"map": map.name, "tier": tier_name(t), "region": region_name, "count": count})


func _act() -> Dictionary:
	var acts: Array = data.get("acts", [])
	if acts.is_empty():
		return {}
	return acts[clampi(state.act, 0, acts.size() - 1)]


func _tiers() -> Array:
	return _act().get("tiers", [])


func _fortify() -> Dictionary:
	return data.get("fortify", {})
