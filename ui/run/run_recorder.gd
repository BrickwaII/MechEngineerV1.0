class_name RunRecorder
extends RefCounted
## Writes the run journal (tools/run_journal.gd) and keeps the run folder's
## summary up to date. RunFlow makes one per run and points it at the
## campaign and battle screen in play; the recorder listens to their signals
## (Campaign.acted, fight_started, fight_finished, expanded, changed;
## BattleScreen.command_sent; FightCommandHandler.action_resolved with the
## Fight's FightEvents) and writes a line for each.
##
## Play time: real seconds while the run is open, over every session, with
## F8 pauses (pause() / unpause()) left out.

## A snapshot was written. RunFlow autosaves on some of them.
signal snapshot_written(reason: String)
## The run ended (lost everything, or the boss fight is over).
signal run_ended(won: bool)

var dir := ""
var journal := RunJournal.new()
var summary: Dictionary = {}
## The campaign in play, or null before the map. Its act and day stamp lines.
var campaign: Campaign
var squad: BotSquad
var ledger: SkillUseLedger
## Returns the fight-side variants (FightVariants) the next fight plays with.
var fight_variants_source: Callable = func() -> FightVariants: return FightVariants.load_active()
## Returns the campaign variants (CampaignVariants) the next fight starts with.
var campaign_variants_source: Callable = func() -> CampaignVariants: return CampaignVariants.load_active()
## Returns the seed a fight request plays with.
var fight_seed_source: Callable = func(_request: FightRequest) -> int: return 0
## Returns the Fight the last fight played, or null (a stub service).
var last_fight_source: Callable = func() -> Fight: return null
## True when fights resolve headless (AutoFightService), with no commands.
var auto_fights := false
## Returns the wall clock as Unix seconds; tests replace it.
var clock: Callable = func() -> float: return Time.get_unix_time_from_system()

var _play_base := 0.0
var _session_start_ms := 0
var _paused_ms := 0
var _pause_started_ms := -1
var _fight_count := 0
var _fight_started_s := 0.0
var _bots_before_fight: Dictionary = {}
var _fight_request: FightRequest
var _snapshot_due := false
var _last_result: FightResult
var _ended := false
var _draft_opened_s := 0.0
## Player actions resolve inside the command that caused them; their lines
## wait here and follow the command's line.
var _held: Array[Dictionary] = []
var _battle: BattleScreen


## Starts a new run's journal and summary in `p_dir`.
func start(p_dir: String, seed_value: int, info: Dictionary) -> void:
	_open(p_dir)
	summary = RunFolder.new_summary(seed_value, p_dir)
	var line := {"kind": RunJournal.KIND_RUN_START, "seed": seed_value, "journal_version": RunJournal.VERSION}
	line.merge(info)
	write(line)
	write({"kind": RunJournal.KIND_SESSION, "event": "start"})
	_write_summary()


## Opens an existing run's journal to carry on: a new session.
func resume(p_dir: String) -> void:
	_open(p_dir)
	summary = RunFolder.read_summary(p_dir)
	if summary.is_empty():
		summary = RunFolder.new_summary(0, p_dir)
	_play_base = float(summary.get("play_s", 0.0))
	_fight_count = _count_fights()
	write({"kind": RunJournal.KIND_SESSION, "event": "resume"})


## Closes the session: its last line, the summary, the file.
func finish() -> void:
	if not journal.is_open():
		return
	write({"kind": RunJournal.KIND_SESSION, "event": "end"})
	_write_summary()
	journal.close()
	watch_campaign(null)


func _open(p_dir: String) -> void:
	finish()
	dir = p_dir
	journal.open(RunFolder.journal_path(p_dir))
	_play_base = 0.0
	_session_start_ms = Time.get_ticks_msec()
	_paused_ms = 0
	_pause_started_ms = -1
	_ended = false


func _count_fights() -> int:
	var n := 0
	for line in RunJournal.read_file(journal.path):
		if line.get("kind") == RunJournal.KIND_FIGHT_START:
			n = maxi(n, int(line.get("fight", 0)))
	return n


# --- Time ---------------------------------------------------------------------------

## Real seconds played in this run so far.
func play_seconds() -> float:
	var now := Time.get_ticks_msec()
	var paused := _paused_ms + (now - _pause_started_ms if _pause_started_ms >= 0 else 0)
	return _play_base + float(now - _session_start_ms - paused) / 1000.0


func pause() -> void:
	if _pause_started_ms < 0:
		_pause_started_ms = Time.get_ticks_msec()


func unpause() -> void:
	if _pause_started_ms >= 0:
		_paused_ms += Time.get_ticks_msec() - _pause_started_ms
		_pause_started_ms = -1


## Appends a line stamped with the wall clock, play time and in-game time.
func write(line: Dictionary) -> Dictionary:
	var unix: float = clock.call()
	var stamped := {
		"kind": line.get("kind", ""),
		"ts": Time.get_datetime_string_from_unix_time(int(unix + _utc_offset_s()), true)
			+ ".%03d" % int(fmod(unix, 1.0) * 1000.0),
		"unix": unix,
		"play_s": snappedf(play_seconds(), 0.001),
	}
	if campaign != null:
		stamped["act"] = campaign.state.act
		stamped["day"] = campaign.day()
		stamped["tp"] = campaign.state.time_points
	stamped.merge(line, true)
	return journal.write(stamped)


static func _utc_offset_s() -> float:
	return float(Time.get_time_zone_from_system().get("bias", 0)) * 60.0


# --- Draft and map -------------------------------------------------------------

func draft_open(bots: Array[Bot]) -> void:
	_draft_opened_s = play_seconds()
	var offered := []
	for bot in bots:
		offered.append(RunJournal.bot_snapshot(bot))
	write({"kind": RunJournal.KIND_DRAFT_OPEN, "offered": offered})


func draft_done(picks: Array[String]) -> void:
	write({"kind": RunJournal.KIND_DRAFT_DONE, "picks": Array(picks),
		"seconds": snappedf(play_seconds() - _draft_opened_s, 0.001)})


## The map is up with its first campaign: the start and the first snapshot.
func map_start(c: Campaign) -> void:
	watch_campaign(c)
	summary.stage = "map"
	write({"kind": RunJournal.KIND_MAP_START, "start_id": c.state.start_id,
		"run_variants": Dictionary(c.state.variants), "region_set_id": c.state.region_set_id})
	snapshot(RunJournal.SNAPSHOT_RUN_START)


## Follows `c` from now on (the next act, a load); null stops following.
func watch_campaign(c: Campaign) -> void:
	if campaign != null:
		for pair in _campaign_handlers():
			if campaign.is_connected(pair[0], pair[1]):
				campaign.disconnect(pair[0], pair[1])
	campaign = c
	if campaign != null:
		for pair in _campaign_handlers():
			campaign.connect(pair[0], pair[1])


func _campaign_handlers() -> Array:
	return [["acted", _on_acted], ["fight_started", _on_fight_started], ["fight_finished", _on_fight_finished],
		["expanded", _on_expanded], ["changed", _on_changed]]


## A map action that is not a Campaign call: focus, save, load, act_zoom.
func action(name: String, region_id := "", extra: Dictionary = {}) -> void:
	var line := {"kind": RunJournal.KIND_ACTION, "action": name}
	if not region_id.is_empty():
		line["region"] = region_id
		line["region_name"] = _region_name(region_id)
	line.merge(extra)
	write(line)


## The state and every bot, now.
func snapshot(reason: String) -> void:
	if campaign == null:
		return
	write({"kind": RunJournal.KIND_SNAPSHOT, "reason": reason,
		"regions_total": campaign.map.regions.size(),
		"state": RunJournal.state_snapshot(campaign),
		"squad": RunJournal.squad_snapshot(squad, ledger)})
	_update_summary()
	snapshot_written.emit(reason)


func feedback(folder: String, category: String, rating: int) -> void:
	write({"kind": RunJournal.KIND_FEEDBACK, "folder": folder, "category": category, "rating": rating})


func is_ended() -> bool:
	return _ended


func _region_name(region_id: String) -> String:
	if campaign != null and campaign.map.has_region(region_id):
		return campaign.map.get_region(region_id).name
	return region_id


func _on_acted(p_action: Campaign.Action, region_id: String) -> void:
	action(RunJournal.ACTION_WAIT if p_action == Campaign.Action.WAIT else RunJournal.ACTION_REINFORCE, region_id)


func _on_expanded(region_id: String) -> void:
	write({"kind": RunJournal.KIND_EXPANDED, "region": region_id, "region_name": _region_name(region_id)})


# --- Fights ---------------------------------------------------------------------------

func _on_fight_started(request: FightRequest) -> void:
	_fight_request = request
	_fight_count += 1
	var name := RunJournal.ACTION_ATTACK
	if request.kind == FightRequest.Kind.DEFEND:
		name = RunJournal.ACTION_DEFEND
	elif request.territory_id == Campaign.BOSS_ID:
		name = RunJournal.ACTION_BOSS
	action(name, request.territory_id if name != RunJournal.ACTION_BOSS else "")
	var fv: FightVariants = fight_variants_source.call()
	var cv: CampaignVariants = campaign_variants_source.call()
	var line := {
		"kind": RunJournal.KIND_FIGHT_START,
		"fight": _fight_count,
		"fight_kind": FightRequest.Kind.keys()[request.kind].to_lower(),
		"territory": request.territory_id,
		"territory_name": _region_name(request.territory_id),
		"level": request.defense_level,
		"seed": fight_seed_source.call(request),
		"squad": request.squad.map(func(m: SquadMemberSummary) -> String: return m.id),
		"fight_variants": Dictionary(fv.non_default()),
		"campaign_variants": Dictionary(cv.non_default()),
	}
	if auto_fights:
		line["auto"] = true
	write(line)
	_bots_before_fight = RunJournal.normalize(RunJournal.squad_snapshot(squad, ledger))
	_fight_started_s = play_seconds()


## Records the commands and resolved actions of the battle on `screen`.
func watch_battle(screen: BattleScreen) -> void:
	_battle = screen
	_held.clear()
	screen.command_sent.connect(_on_command_sent)
	screen.handler.action_resolved.connect(_on_action_resolved.bind(screen.fight))


func _on_command_sent(command: FightCommand, problem: String) -> void:
	write(RunJournal.command_line(command, problem))
	for line in _held:
		write(line)
	_held.clear()


func _on_action_resolved(actor_id: String, tag: String, fight: Fight) -> void:
	var line := RunJournal.resolved_line(fight, actor_id, tag)
	if line.side == "player" and _battle != null and _battle.fight == fight:
		_held.append(line)
	else:
		write(line)


func _on_fight_finished(request: FightRequest, result: FightResult) -> void:
	for line in _held:
		write(line)
	_held.clear()
	_battle = null
	var won := result.is_victory()
	summary.fights_won = int(summary.get("fights_won", 0)) + (1 if won else 0)
	summary.fights_lost = int(summary.get("fights_lost", 0)) + (0 if won else 1)
	var fight: Fight = last_fight_source.call()
	write({
		"kind": RunJournal.KIND_FIGHT_END,
		"fight": _fight_count,
		"outcome": "victory" if won else "defeat",
		"actions": fight.action_count if fight != null else -1,
		"timed_out": fight.timed_out if fight != null else false,
		"grid_cost": result.grid_cost,
		"rewards": Dictionary(result.rewards),
		"seconds": snappedf(play_seconds() - _fight_started_s, 0.001),
	})
	var after := RunJournal.squad_snapshot(squad, ledger)
	write({"kind": RunJournal.KIND_POST_FIGHT, "fight": _fight_count,
		"changes": RunJournal.bot_changes(_bots_before_fight, RunJournal.normalize(after))})
	_last_result = result
	_fight_request = request
	_snapshot_due = true


## After a fight's result is applied to the map: the snapshot, and the end of
## the run when it ended.
func _on_changed() -> void:
	if campaign == null or campaign.fighting:
		return
	if _snapshot_due:
		_snapshot_due = false
		snapshot(RunJournal.SNAPSHOT_FIGHT)
		if _fight_request != null and _fight_request.territory_id == Campaign.BOSS_ID:
			_end(_last_result.is_victory(), "boss fight won" if _last_result.is_victory() else "boss fight lost")
			return
	if campaign.is_lost():
		_end(false, "every region lost")


func _end(won: bool, reason: String) -> void:
	if _ended:
		return
	_ended = true
	summary.finished = true
	summary.won = won
	write({"kind": RunJournal.KIND_RUN_END, "won": won, "reason": reason})
	_write_summary()
	run_ended.emit(won)


# --- Summary -------------------------------------------------------------------------

func _update_summary() -> void:
	if campaign != null:
		summary.stage = "map"
		summary.act = campaign.state.act + 1
		summary.day = campaign.day()
		summary.regions_held = campaign.state.owned.size()
		summary.regions_total = campaign.map.regions.size()
	_write_summary()


func _write_summary() -> void:
	if dir.is_empty():
		return
	summary.play_s = snappedf(play_seconds(), 0.001)
	summary.updated_unix = clock.call()
	RunFolder.write_summary(dir, summary)


## Sets the summary's act name (the map screen knows it).
func set_act_name(act_name: String) -> void:
	summary.act_name = act_name
	_write_summary()
