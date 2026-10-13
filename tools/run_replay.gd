class_name RunReplay
extends RefCounted
## Re-plays a run headless from its journal (RunJournal): the seeded draft
## and the picks, every map action on a real Campaign, every fight from its
## recorded commands (or headless, for a fight that was auto-played), the
## post-fight changes, act zooms, saves and loads. At each snapshot line it
## compares its own state and bots with the journal's. Fights are
## deterministic for a seed, so any difference is a bug.
##
##   var replay := RunReplay.new(RunJournal.read_file(path))
##   await replay.run()
##   replay.mismatches   # [] when the run re-plays exactly
##
## Needs a running SceneTree: a FightService reports a frame after it starts,
## so run() awaits frames.

const ACTS_FILE := "res://data/tuning/acts.json"

## Every difference found, "line N (kind): what".
var mismatches: Array[String] = []
var snapshots_checked := 0
var fights_played := 0
var lines: Array[Dictionary] = []
## True once the whole journal was read through.
var finished := false

var settings: RunDataSettings
var squad: BotSquad
var ledger: SkillUseLedger
var plan: ActPlan
var campaign: Campaign

var _i := 0
var _seed := 0
var _bot_tuning: BotTuning
var _region_file := ""
var _service: ReplayFightService
## The run as it stood at the last save line, for a load.
var _saved: Dictionary = {}


## A FightService that plays each fight from the journal's lines.
class ReplayFightService:
	extends FightService
	var replay: RunReplay

	func _init(p_replay: RunReplay) -> void:
		replay = p_replay

	func start_fight(request: FightRequest) -> void:
		var result := replay._play_fight(request)
		Engine.get_main_loop().process_frame.connect(func() -> void: finished.emit(result), CONNECT_ONE_SHOT)


func _init(p_lines: Array[Dictionary], p_settings: RunDataSettings = null) -> void:
	lines = p_lines
	settings = p_settings if p_settings != null else RunDataSettings.load_default()
	_service = ReplayFightService.new(self)


func is_match() -> bool:
	return finished and mismatches.is_empty()


## Re-plays every line. Await it.
func run() -> void:
	if lines.is_empty() or lines[0].get("kind") != RunJournal.KIND_RUN_START:
		_mismatch({}, "the journal does not start with run_start (an imported or partial run): nothing to replay")
		_service.replay = null
		return
	while _i < lines.size():
		var line := lines[_i]
		_i += 1
		await _step(line)
	finished = true
	# The campaign, its fight service and this replay point at each other.
	campaign = null
	_service.replay = null


func _step(line: Dictionary) -> void:
	match str(line.get("kind", "")):
		RunJournal.KIND_RUN_START:
			_run_start(line)
		RunJournal.KIND_DRAFT_OPEN:
			_draft_open(line)
		RunJournal.KIND_DRAFT_DONE:
			_draft_done(line)
		RunJournal.KIND_MAP_START:
			_map_start(line)
		RunJournal.KIND_SNAPSHOT:
			_check_snapshot(line)
		RunJournal.KIND_ACTION:
			await _action(line)
		RunJournal.KIND_FIGHT_START, RunJournal.KIND_COMMAND, RunJournal.KIND_RESOLVED, \
				RunJournal.KIND_FIGHT_END, RunJournal.KIND_POST_FIGHT:
			_mismatch(line, "a fight line with no fight in progress")


func _mismatch(line: Dictionary, text: String) -> void:
	mismatches.append("line %s (%s): %s" % [line.get("seq", "?"), line.get("kind", "?"), text])


# --- Draft and map -------------------------------------------------------------

func _run_start(line: Dictionary) -> void:
	_seed = int(line.get("seed", 0))
	_bot_tuning = BotTuning.load_default()
	var rule := str(line.get("draft_rule", ""))
	if rule in BotTuning.DRAFT_RULES:
		_bot_tuning.draft_rule = rule
	if line.has("draft_size"):
		_bot_tuning.draft_size = int(line.draft_size)
	if line.has("squad_size"):
		_bot_tuning.squad_size = int(line.squad_size)
	_region_file = str(line.get("region_file", ""))
	plan = ActPlan.load_file(ACTS_FILE)
	var act_variants: Array = line.get("act_variants", [])
	for act in mini(act_variants.size(), plan.act_count()):
		if not plan.choose_variant(act, str(act_variants[act])):
			_mismatch(line, "act %d has no map variant '%s'" % [act + 1, act_variants[act]])


func _draft_open(line: Dictionary) -> void:
	var offered := []
	for bot in BotFactory.new(_bot_tuning).build_draft(_seed):
		offered.append(RunJournal.bot_snapshot(bot))
	_compare(line, "draft", line.get("offered", []), offered)


## The seeded draft with the recorded picks, bench dropped, as the draft
## screen's DraftPicker and RunFlow leave it.
func _draft_done(line: Dictionary) -> void:
	var picks: Array[String] = []
	for bot_id: Variant in line.get("picks", []):
		picks.append(str(bot_id))
	var drafted := BotSquad.new(BotFactory.new(_bot_tuning).build_draft(_seed), picks, _bot_tuning.squad_size)
	for problem in drafted.validation_errors():
		_mismatch(line, problem)
	if picks.size() != _bot_tuning.squad_size:
		_mismatch(line, "%d picks for a squad of %d" % [picks.size(), _bot_tuning.squad_size])
	squad = drafted.to_fielded_squad()
	ledger = SkillUseLedger.new()


func _map_start(line: Dictionary) -> void:
	if squad == null:
		_mismatch(line, "the map started with no drafted squad")
		return
	var map := _map_for(0)
	var tuning := plan.load_tuning(0)
	var start := map.get_start(str(line.get("start_id", "")))
	if start == null:
		_mismatch(line, "no start '%s' on map '%s'" % [line.get("start_id"), map.id])
		return
	var run_variants := CampaignVariants.for_run(line.get("run_variants", {}))
	_use(map, tuning, Campaign.new_run_state(map, tuning, start, run_variants))


func _map_for(act: int) -> RegionMap:
	return RegionMap.load_file(_region_file) if act == 0 and not _region_file.is_empty() else plan.load_map(act)


func _use(map: RegionMap, tuning: MapTuning, state: RunState) -> void:
	campaign = Campaign.new(map, tuning, BotSquadProvider.new(squad), _service, state)
	campaign.next_fight_variants = _next_campaign_variants


## The campaign variants the next fight_start line recorded.
func _next_campaign_variants() -> CampaignVariants:
	var v := CampaignVariants.defaults()
	for j in range(_i, lines.size()):
		if lines[j].get("kind") == RunJournal.KIND_FIGHT_START:
			var chosen: Dictionary = lines[j].get("campaign_variants", {})
			for decision: Variant in chosen:
				v.choose(str(decision), str(chosen[decision]))
			break
	return v


func _check_snapshot(line: Dictionary) -> void:
	if campaign == null:
		_mismatch(line, "a snapshot before the map started")
		return
	snapshots_checked += 1
	var expected: Dictionary = line.get("state", {})
	var actual := RunJournal.state_snapshot(campaign)
	for key in RunJournal.LATER_STATE_KEYS:
		if not expected.has(key):
			actual.erase(key)
	_compare(line, "state", expected, actual)
	_compare(line, "squad", line.get("squad", {}), RunJournal.squad_snapshot(squad, ledger))


func _compare(line: Dictionary, what: String, expected: Variant, actual: Variant) -> void:
	for d in RunJournal.differences(expected, actual, settings.replay_float_tolerance, what):
		_mismatch(line, d)


func _action(line: Dictionary) -> void:
	if campaign == null:
		_mismatch(line, "a map action before the map started")
		return
	var region := str(line.get("region", ""))
	var done := true
	match str(line.get("action", "")):
		RunJournal.ACTION_WAIT:
			done = campaign.wait()
		RunJournal.ACTION_REINFORCE:
			done = campaign.reinforce(region)
		RunJournal.ACTION_FOCUS:
			campaign.set_focus(region)
		RunJournal.ACTION_ATTACK:
			done = await campaign.attack(region, bool(line.get("breach", false)))
		RunJournal.ACTION_RETREAT:
			done = campaign.retreat(region)
		RunJournal.ACTION_REPAIR:
			done = campaign.repair()
		RunJournal.ACTION_FAST_FORWARD:
			done = not campaign.fast_forward().is_empty()
		RunJournal.ACTION_DEFEND:
			done = await campaign.defend()
		RunJournal.ACTION_BOSS:
			done = await campaign.boss_fight() != null
		RunJournal.ACTION_ACT_ZOOM:
			done = _zoom()
		RunJournal.ACTION_SAVE:
			_save()
		RunJournal.ACTION_LOAD:
			done = _load(line)
		RunJournal.ACTION_EXIT:
			pass
	if not done:
		_mismatch(line, "%s %s was not allowed here" % [line.get("action"), region])


func _zoom() -> bool:
	if not plan.has_next(campaign.state.act):
		return false
	var next := campaign.state.act + 1
	var map := _map_for(next)
	var tuning := plan.load_tuning(next)
	_use(map, tuning, plan.zoom_state(campaign.state, map, tuning))
	return true


func _save() -> void:
	_saved = {
		"state": campaign.state.duplicate_state(),
		"squad": squad.duplicate(true),
		"ledger": ledger.duplicate(true),
	}


func _load(line: Dictionary) -> bool:
	if _saved.is_empty():
		_mismatch(line, "a load with no save earlier in the journal")
		return false
	squad = (_saved.squad as BotSquad).duplicate(true)
	ledger = (_saved.ledger as SkillUseLedger).duplicate(true)
	var state: RunState = (_saved.state as RunState).duplicate_state()
	if not plan.choose_variant(state.act, state.region_set_id) and not (state.act == 0 and not _region_file.is_empty()):
		return false
	_use(_map_for(state.act), plan.load_tuning(state.act), state)
	return true


# --- Fights ----------------------------------------------------------------------

## Plays the fight the next lines recorded and applies its aftermath to the
## bots, as RunFightService does. Moves past the fight's lines.
func _play_fight(request: FightRequest) -> FightResult:
	if _i >= lines.size() or lines[_i].get("kind") != RunJournal.KIND_FIGHT_START:
		_mismatch(lines[_i - 1], "a fight started with no fight_start line next")
		return FightResult.new(FightResult.Outcome.DEFEAT)
	var start := lines[_i]
	_i += 1
	fights_played += 1
	if str(start.get("territory")) != request.territory_id or int(start.get("level", -1)) != request.defense_level \
			or str(start.get("fight_kind")) != FightRequest.Kind.keys()[request.kind].to_lower():
		_mismatch(start, "the journal fought %s %s at level %s, the replay %s at level %d" % [
			start.get("fight_kind"), start.get("territory"), start.get("level"), request.territory_id, request.defense_level])
	var fv := FightVariants.defaults()
	var chosen: Dictionary = start.get("fight_variants", {})
	for decision: Variant in chosen:
		fv.choose(str(decision), str(chosen[decision]))
	var cv := _next_campaign_variants_at(start)
	var tuning := CombatTuning.load_default().with_variants(fv)
	var seed_value := int(start.get("seed", 0))
	var fight: Fight
	if bool(start.get("auto", false)):
		fight = HeadlessFightRunner.run(request, seed_value, SimpleFightPolicy.new(), IntentFightPolicy.new(), tuning)
	else:
		fight = _play_commands(request, seed_value, tuning)
	var end := _take(RunJournal.KIND_FIGHT_END)
	if str(end.get("outcome", "")) == RunJournal.OUTCOME_ABANDONED:
		# The player left mid-battle: the real run applied nothing and goes on
		# from the save made before the fight, at the next load line. The
		# replay's campaign takes a defeat here that the load then replaces.
		return FightResult.new(FightResult.Outcome.DEFEAT)
	if end.is_empty():
		_mismatch(start, "the fight's lines have no fight_end")
	else:
		var outcome := "victory" if fight.outcome == FightResult.Outcome.VICTORY else "defeat"
		if not fight.is_over():
			_mismatch(end, "the replayed fight is not over")
		if str(end.get("outcome")) != outcome:
			_mismatch(end, "outcome: expected %s, got %s" % [end.get("outcome"), outcome])
		if int(end.get("actions", -1)) >= 0 and int(end.actions) != fight.action_count:
			_mismatch(end, "actions: expected %s, got %d" % [end.actions, fight.action_count])
	var before: Variant = RunJournal.normalize(RunJournal.squad_snapshot(squad, ledger))
	FightAftermath.apply(fight, squad, ledger, fv)
	var post := _take(RunJournal.KIND_POST_FIGHT)
	if not post.is_empty():
		var changes := RunJournal.bot_changes(before, RunJournal.normalize(RunJournal.squad_snapshot(squad, ledger)))
		_compare(post, "post_fight", post.get("changes", {}), changes)
	return GridCostOwner.service_result(request.kind, fight.result(), cv)


func _next_campaign_variants_at(start: Dictionary) -> CampaignVariants:
	var v := CampaignVariants.defaults()
	var chosen: Dictionary = start.get("campaign_variants", {})
	for decision: Variant in chosen:
		v.choose(str(decision), str(chosen[decision]))
	return v


## The next line if it is of `kind` (moving past it), else {}.
func _take(kind: String) -> Dictionary:
	if _i < lines.size() and lines[_i].get("kind") == kind:
		_i += 1
		return lines[_i - 1]
	return {}


## Feeds the recorded commands to a FightCommandHandler, as the battle screen
## did, and checks every resolved action against the journal.
func _play_commands(request: FightRequest, seed_value: int, tuning: CombatTuning) -> Fight:
	var fight := Fight.new(request, seed_value, tuning)
	var handler := FightCommandHandler.new(fight, IntentFightPolicy.new(), false)
	var produced: Array[Dictionary] = []
	handler.action_resolved.connect(func(actor_id: String, tag: String) -> void:
		produced.append(RunJournal.resolved_line(fight, actor_id, tag)))
	while _i < lines.size():
		var line := lines[_i]
		var kind := str(line.get("kind"))
		if kind == RunJournal.KIND_COMMAND:
			_i += 1
			var command := RunJournal.command_from(line)
			if command == null:
				_mismatch(line, "unknown command %s" % line.get("cmd"))
				continue
			var problem := handler.apply(command)
			if problem != str(line.get("problem", "")):
				_mismatch(line, "%s: expected \"%s\", got \"%s\"" % [command, line.get("problem", ""), problem])
		elif kind == RunJournal.KIND_RESOLVED:
			_i += 1
			if produced.is_empty() and line.get("side") == "enemy":
				handler.resolve_enemy_turn()
			if produced.is_empty():
				_mismatch(line, "the replay resolved no action here")
				continue
			_compare(line, "resolved", _resolved_part(line), _resolved_part(produced.pop_front()))
		else:
			break
	for extra in produced:
		mismatches.append("fight %d: the replay resolved %s %s with no journal line" % [fights_played, extra.actor, extra.tag])
	return fight


static func _resolved_part(line: Dictionary) -> Dictionary:
	return {"index": line.get("index"), "actor": line.get("actor"), "side": line.get("side"),
		"tag": line.get("tag"), "events": line.get("events")}
