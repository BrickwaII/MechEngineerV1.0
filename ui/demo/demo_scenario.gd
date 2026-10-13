class_name DemoScenario
extends RefCounted
## One demo scenario: a ready-made moment of a run to jump straight into from
## the main menu's DEMO picker, never saved. Read from data/demo/<id>.json
## (format in data/demo/README.md) and built only through the public APIs of
## campaign/ (ActPlan, RegionMap, MapTuning, Campaign.new_run_state, RunState),
## bot_data/ (BotFactory, BotSquad) and fight/ (FightRequest, EnemyTable).
##
## Kinds:
##   map           the act's map in the scenario's state
##   fight         the map behind, and a battle on top at once
##   pre_fight     the map with the pre-fight step (Fight, Breach, Retreat)
##                 open on `region`
##   fast_forward  the map, then FAST-FORWARD to the payload and its summary
##   run_over      the run-over screen, from `run_over`
## A map whose state has a held region at full pressure opens on its forced
## defense, as a loaded run does.

const DEFAULT_DIR := "res://data/demo"
const ACTS_FILE := "res://data/tuning/acts.json"

const KIND_MAP := "map"
const KIND_FIGHT := "fight"
const KIND_PRE_FIGHT := "pre_fight"
const KIND_FAST_FORWARD := "fast_forward"
const KIND_RUN_OVER := "run_over"
const KINDS: Array[String] = [KIND_MAP, KIND_FIGHT, KIND_PRE_FIGHT, KIND_FAST_FORWARD, KIND_RUN_OVER]

## Fortify key that applies to every hostile region.
const EVERY_HOSTILE := "*"
## Music for a fight scenario.
const MUSIC_BATTLE := "battle"
const MUSIC_BOSS := "boss"

## The file name without .json.
var id := ""
var path := ""
var scenario_name := ""
var description := ""
## An icon id from data/ui/icons.json.
var icon := "unknown"
## 1 to 3.
var act := 1
## Place among the act's cards, lowest first.
var order := 0
var kind := KIND_MAP
## Map variant id ("" for the act's default) and start id ("" for the first).
var map_variant := ""
var start_id := ""
## Held region ids; empty keeps the start's. hostile lists the regions NOT
## held instead (every other region is held).
var held: PackedStringArray = []
var hostile: PackedStringArray = []
## Region id -> pressure percent on a held region.
var pressure: Dictionary = {}
var alert_tier := 0
## Region id (or "*" for every hostile region) -> fortification levels.
var fortify: Dictionary = {}
## energy, material, grid; missing ones keep the act's start values.
var resources: Dictionary = {}
var day := 1
var losses := 0
## A news card to toast on arrival: {} for none, {"kind": "tier"} for the
## act's own headline at the alert tier, or {"headline", "body"}.
var news: Dictionary = {}
## {"seed", "picks", "skill_ranks"}: the seeded draft's squad (picks in
## order, or the draft's own first picks), each skill raised skill_ranks.
var squad: Dictionary = {}
## Fight scenarios: {"region", "kind" (attack or defend), "level",
## "enemies" (ids, optional), "boss", "music"}.
var fight: Dictionary = {}
## Pre-fight scenarios: the region the step opens on.
var region := ""
## Run-over scenarios: the summary RunOverScreen shows.
var run_over: Dictionary = {}
## Why the file cannot be played; empty when it can.
var errors: Array[String] = []


## Every scenario in `dir`, sorted by act then order then id. Files starting
## with "_" are skipped.
static func load_all(dir := DEFAULT_DIR) -> Array[DemoScenario]:
	var out: Array[DemoScenario] = []
	for file in DirAccess.get_files_at(dir):
		if file.get_extension() != "json" or file.begins_with("_"):
			continue
		out.append(load_file(dir.path_join(file)))
	out.sort_custom(func(a: DemoScenario, b: DemoScenario) -> bool:
		if a.act != b.act:
			return a.act < b.act
		if a.order != b.order:
			return a.order < b.order
		return a.id < b.id)
	return out


static func load_file(p_path: String) -> DemoScenario:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(p_path))
	var s := from_dict(parsed if parsed is Dictionary else {}, p_path.get_file().get_basename())
	s.path = p_path
	if not parsed is Dictionary:
		s.errors.append("%s is not a JSON object" % p_path)
	return s


static func from_dict(d: Dictionary, p_id: String) -> DemoScenario:
	var s := DemoScenario.new()
	s.id = p_id
	s.scenario_name = str(d.get("name", ""))
	s.description = str(d.get("description", ""))
	s.icon = str(d.get("icon", "unknown"))
	s.act = int(d.get("act", 1))
	s.order = int(d.get("order", 0))
	s.kind = str(d.get("kind", KIND_MAP))
	s.map_variant = str(d.get("map", ""))
	s.start_id = str(d.get("start", ""))
	s.held = PackedStringArray(d.get("held", []))
	s.hostile = PackedStringArray(d.get("hostile", []))
	s.pressure = (d.get("pressure", {}) as Dictionary).duplicate()
	s.alert_tier = int(d.get("alert_tier", 0))
	s.fortify = (d.get("fortify", {}) as Dictionary).duplicate()
	s.resources = (d.get("resources", {}) as Dictionary).duplicate()
	s.day = int(d.get("day", 1))
	s.losses = int(d.get("losses", 0))
	var news_value: Variant = d.get("news", {})
	s.news = news_value.duplicate() if news_value is Dictionary else {}
	s.squad = (d.get("squad", {}) as Dictionary).duplicate(true)
	s.fight = (d.get("fight", {}) as Dictionary).duplicate(true)
	s.region = str(d.get("region", ""))
	s.run_over = (d.get("run_over", {}) as Dictionary).duplicate(true)
	s._check_fields()
	return s


func is_valid() -> bool:
	return errors.is_empty()


## The act index (0 for act 1), as RunState keeps it.
func act_index() -> int:
	return act - 1


func is_fight() -> bool:
	return kind == KIND_FIGHT


func is_boss() -> bool:
	return is_fight() and bool(fight.get("boss", false))


## "boss" or "battle".
func music() -> String:
	return str(fight.get("music", MUSIC_BOSS if is_boss() else MUSIC_BATTLE))


func _check_fields() -> void:
	if scenario_name.is_empty():
		errors.append("%s: no name" % id)
	if description.is_empty():
		errors.append("%s: no description" % id)
	if not kind in KINDS:
		errors.append("%s: kind '%s' is not one of %s" % [id, kind, ", ".join(KINDS)])
	if act < 1 or act > 3:
		errors.append("%s: act %d is not 1 to 3" % [id, act])
	if not UiIcons.has(icon):
		errors.append("%s: no icon '%s' in data/ui/icons.json" % [id, icon])
	if not held.is_empty() and not hostile.is_empty():
		errors.append("%s: give held or hostile, not both" % id)
	if day < 1:
		errors.append("%s: day %d is before day 1" % [id, day])
	if kind == KIND_FIGHT:
		if str(fight.get("region", "")).is_empty():
			errors.append("%s: a fight needs fight.region" % id)
		var level := int(fight.get("level", -1))
		if level < FightRequest.MIN_DEFENSE_LEVEL or level > FightRequest.MAX_DEFENSE_LEVEL:
			errors.append("%s: fight.level %d is outside %d to %d" % [
				id, level, FightRequest.MIN_DEFENSE_LEVEL, FightRequest.MAX_DEFENSE_LEVEL])
		if not str(fight.get("kind", "attack")) in ["attack", "defend"]:
			errors.append("%s: fight.kind must be attack or defend" % id)
		if not music() in [MUSIC_BATTLE, MUSIC_BOSS]:
			errors.append("%s: fight.music must be battle or boss" % id)
	if kind == KIND_PRE_FIGHT and region.is_empty():
		errors.append("%s: a pre_fight scenario needs region" % id)


# --- Building ---------------------------------------------------------------------

## The act plan with this scenario's map chosen for its act.
func act_plan() -> ActPlan:
	var plan := ActPlan.load_file(ACTS_FILE)
	if plan.is_valid() and act_index() < plan.act_count():
		plan.choose_variant(act_index(), map_variant)
	return plan


## The map state this scenario starts from, or null when it does not fit its
## map (the problems go to `problems`).
func build_state(problems: Array[String] = []) -> RunState:
	var plan := act_plan()
	if not plan.is_valid() or act_index() >= plan.act_count():
		problems.append("%s: the acts file has no act %d" % [id, act])
		return null
	if not map_variant.is_empty() and plan.chosen_variant(act_index()) != map_variant:
		problems.append("%s: act %d has no map '%s'" % [id, act, map_variant])
		return null
	var map := plan.load_map(act_index())
	var tuning := plan.load_tuning(act_index())
	if not map.is_valid() or not tuning.is_valid():
		problems.append("%s: the act's map or tuning does not load" % id)
		return null
	var start := map.get_start(start_id)
	if start == null:
		problems.append("%s: no start '%s' on %s" % [id, start_id, map.id])
		return null
	var s := Campaign.new_run_state(map, tuning, start, CampaignVariants.defaults())
	s.act = act_index()
	var owned := held if not held.is_empty() else s.owned
	if not hostile.is_empty():
		owned = PackedStringArray()
		for region_id in map.ids():
			if not region_id in hostile:
				owned.append(region_id)
	for region_id in Array(owned) + Array(hostile) + pressure.keys():
		if not map.has_region(str(region_id)):
			problems.append("%s: %s has no region '%s'" % [id, map.id, region_id])
	if owned.is_empty():
		problems.append("%s: holds no region" % id)
	if not problems.is_empty():
		return null
	s.owned = PackedStringArray()
	for region_id in map.ids():
		if region_id in owned:
			s.owned.append(region_id)
	s.pressure.clear()
	for region_id in s.owned:
		s.pressure[region_id] = float(pressure.get(region_id, tuning.start_pressure))
	s.energy = float(resources.get("energy", s.energy))
	s.material = float(resources.get("material", s.material))
	s.grid = float(resources.get("grid", s.grid))
	s.time_points = mini((day - 1) * tuning.points_per_day, tuning.total_points)
	s.losses = losses
	s.escalation = {"tier": alert_tier, "fortify": _fortify_of(map, s.owned), "quiet": {}}
	return s


func _fortify_of(map: RegionMap, owned: PackedStringArray) -> Dictionary:
	var out := {}
	for region_id in map.ids():
		if region_id in owned:
			continue
		var levels := int(fortify.get(region_id, fortify.get(EVERY_HOSTILE, 0)))
		if levels > 0:
			out[region_id] = levels
	return out


## The squad: the seeded draft's fielded bots, skills raised by skill_ranks.
func build_squad(problems: Array[String] = []) -> BotSquad:
	var tuning := BotTuning.load_default()
	var seed_value := int(squad.get("seed", 1))
	var picks: Array[String] = []
	for bot_id: Variant in squad.get("picks", []):
		picks.append(str(bot_id))
	var built: BotSquad
	if picks.is_empty():
		built = BotFactory.new(tuning).build_squad(seed_value).to_fielded_squad()
	else:
		built = BotSquad.new(BotFactory.new(tuning).build_draft(seed_value), picks, picks.size()).to_fielded_squad()
		for problem in built.validation_errors():
			problems.append("%s: %s" % [id, problem])
	var ranks := int(squad.get("skill_ranks", 0))
	if ranks != 0:
		var combat := CombatTuning.load_default()
		var top := combat.skill_ranks.max_rank() if combat.skill_ranks != null else Skill.MIN_LEVEL + ranks
		for bot in built.get_fielded():
			for skill in bot.skills:
				if skill != null:
					skill.level = clampi(skill.level + ranks, Skill.MIN_LEVEL, top)
	return built


## The fight a fight scenario plays, for `members`.
func fight_request(members: Array[SquadMemberSummary]) -> FightRequest:
	var fight_kind := FightRequest.Kind.DEFEND if str(fight.get("kind", "attack")) == "defend" else FightRequest.Kind.ATTACK
	return FightRequest.new(fight_kind, str(fight.get("region", "")), int(fight.get("level", 0)), members)


## The enemy table the fight draws from: the shipped one, or one that fields
## the listed enemies every time. Unknown ids go to `problems`.
func enemy_table(problems: Array[String] = []) -> EnemyTable:
	var base := EnemyTable.load_default()
	var listed: Array[String] = []
	for enemy_id: Variant in fight.get("enemies", []):
		if not base.enemies.has(str(enemy_id)):
			problems.append("%s: unknown enemy '%s'" % [id, enemy_id])
			continue
		listed.append(str(enemy_id))
	if listed.is_empty():
		return base
	var table := FixedEnemyTable.from_table(base, listed)
	table.factions = base.factions
	return table


## The news card to toast on arrival, or {}: the act's own tier headline, or
## the scenario's.
func news_card(map: RegionMap) -> Dictionary:
	if news.is_empty():
		return {}
	var data := Escalation.load_data()
	var acts: Array = data.get("acts", [])
	var tiers: Array = (acts[clampi(act_index(), 0, acts.size() - 1)] as Dictionary).get("tiers", []) if not acts.is_empty() else []
	var tier_name := str((tiers[clampi(alert_tier, 0, tiers.size() - 1)] as Dictionary).get("name", "")) if not tiers.is_empty() else ""
	var headline := str(news.get("headline", ""))
	var body := str(news.get("body", ""))
	if str(news.get("kind", "")) == Escalation.NEWS_TIER and headline.is_empty():
		var by_act: Array = data.get("news", {}).get("tiers", [])
		if not by_act.is_empty():
			var act_lines: Array = by_act[clampi(act_index(), 0, by_act.size() - 1)]
			if alert_tier < act_lines.size() and not (act_lines[alert_tier] as Array).is_empty():
				headline = str(act_lines[alert_tier][0])
		body = str(data.get("news", {}).get("tier_body", ""))
	var fill := {"map": map.name, "tier": tier_name, "region": "", "count": 0}
	return {
		"kind": Escalation.NEWS_TIER, "tier": alert_tier, "tier_name": tier_name, "region": "",
		"headline": headline.format(fill), "body": body.format(fill),
	}


## Every problem found by building the scenario, as the demo would.
func problems() -> Array[String]:
	var out: Array[String] = errors.duplicate()
	if not out.is_empty():
		return out
	if kind == KIND_RUN_OVER:
		return out
	var state := build_state(out)
	var built := build_squad(out)
	if state == null:
		return out
	var map := act_plan().load_map(act_index())
	if kind == KIND_FIGHT:
		var territory := str(fight.get("region", ""))
		if territory != Campaign.BOSS_ID and not map.has_region(territory):
			out.append("%s: fight.region '%s' is not on %s" % [id, territory, map.id])
		enemy_table(out)
		if built != null and not fight_request(BotSquadProvider.new(built).get_squad()).is_valid():
			out.append("%s: the fight request is not valid" % id)
	if kind == KIND_PRE_FIGHT and not map.has_region(region):
		out.append("%s: region '%s' is not on %s" % [id, region, map.id])
	return out
