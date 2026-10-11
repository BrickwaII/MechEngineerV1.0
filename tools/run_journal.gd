class_name RunJournal
extends RefCounted
## The run journal: one JSON object per line (JSON Lines), one file per run
## (journal.jsonl in the run's folder). The game appends a line for every
## draft pick, map action, battle command, resolved action, fight start and
## end, post-fight change and state snapshot; tools/replay_run.gd reads it
## back, re-plays the run headless and prints a timeline.
##
## Every line carries:
##   seq     line number in the run, from 1
##   kind    one of the KIND_ constants
##   ts      local wall-clock time, "2026-10-11T14:03:22.125"
##   unix    the same as Unix seconds
##   play_s  real seconds played in this run so far, over every session,
##           F8 pauses left out
##   act, day, tp   in-game time: act index (0 for act 1), day, time points
##           (absent before the map starts)
##
## Lines by kind, past those fields:
##   run_start   seed, journal_version, variants (switchboard choices),
##               draft_rule, draft_size, squad_size, act_variants, region_file
##   session     event: "start" | "resume" | "end"
##   draft_open  offered: [bot]
##   draft_done  picks: [bot id] in pick order, seconds
##   map_start   start_id, run_variants (RunState.variants)
##   snapshot    reason: "run_start" | "fight" | "act" | "load", state, squad
##   action      action: one of the ACTION_ constants, region, region_name
##   fight_start fight (number in the run, from 1), kind, territory,
##               territory_name, level, seed, fight_variants, campaign_variants
##   command     cmd, arg, ticks, problem ("" when accepted)
##   resolved    index, actor, side, tag, events: [event]
##   fight_end   fight, outcome, actions, timed_out, grid_cost, rewards, seconds
##   post_fight  fight, changes: {bot id: {field: [before, after]}}
##   expanded    region, region_name
##   feedback    folder, category, rating
##   run_end     won, reason
##
## A snapshot's state and squad are what state_snapshot() and
## squad_snapshot() give; the replay builds the same from its own run and
## compares (differences()).

const VERSION := 1
const FILE_NAME := "journal.jsonl"

const KIND_RUN_START := "run_start"
const KIND_SESSION := "session"
const KIND_DRAFT_OPEN := "draft_open"
const KIND_DRAFT_DONE := "draft_done"
const KIND_MAP_START := "map_start"
const KIND_SNAPSHOT := "snapshot"
const KIND_ACTION := "action"
const KIND_FIGHT_START := "fight_start"
const KIND_COMMAND := "command"
const KIND_RESOLVED := "resolved"
const KIND_FIGHT_END := "fight_end"
const KIND_POST_FIGHT := "post_fight"
const KIND_EXPANDED := "expanded"
const KIND_FEEDBACK := "feedback"
const KIND_RUN_END := "run_end"

const ACTION_WAIT := "wait"
const ACTION_REINFORCE := "reinforce"
const ACTION_ATTACK := "attack"
const ACTION_DEFEND := "defend"
const ACTION_BOSS := "boss"
const ACTION_FOCUS := "focus"
const ACTION_SAVE := "save"
const ACTION_LOAD := "load"
const ACTION_ACT_ZOOM := "act_zoom"

const SNAPSHOT_RUN_START := "run_start"
const SNAPSHOT_FIGHT := "fight"
const SNAPSHOT_ACT := "act"
const SNAPSHOT_LOAD := "load"

var path := ""
var _file: FileAccess
var _seq := 0


## Opens `p_path` for appending, creating it when missing. Lines already in
## the file keep their numbers; new ones follow on.
func open(p_path: String) -> Error:
	close()
	path = p_path
	_seq = read_file(p_path).size() if FileAccess.file_exists(p_path) else 0
	if not FileAccess.file_exists(p_path):
		var created := FileAccess.open(p_path, FileAccess.WRITE)
		if created == null:
			return FileAccess.get_open_error()
		created.close()
	_file = FileAccess.open(p_path, FileAccess.READ_WRITE)
	if _file == null:
		return FileAccess.get_open_error()
	_file.seek_end()
	return OK


func is_open() -> bool:
	return _file != null


## Appends `line` with its seq number, flushed at once so a crash or a copy
## for the F8 report loses nothing. Returns the line as written.
func write(line: Dictionary) -> Dictionary:
	_seq += 1
	var out := {"seq": _seq}
	out.merge(line)
	if _file != null:
		_file.store_line(JSON.stringify(out, "", false, true))
		_file.flush()
	return out


func close() -> void:
	if _file != null:
		_file.close()
		_file = null


## Every line of the journal at `p_path`, in order. Broken lines are skipped.
static func read_file(p_path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var file := FileAccess.open(p_path, FileAccess.READ)
	if file == null:
		return out
	while not file.eof_reached():
		var text := file.get_line().strip_edges()
		if text.is_empty():
			continue
		var json := JSON.new()
		if json.parse(text) == OK and json.data is Dictionary:
			out.append(json.data)
	return out


# --- Snapshots ----------------------------------------------------------------

## The map side of a snapshot.
static func state_snapshot(c: Campaign) -> Dictionary:
	var s := c.state
	return {
		"region_set_id": s.region_set_id,
		"act": s.act,
		"day": c.day(),
		"time_points": s.time_points,
		"grid": s.grid,
		"energy": s.energy,
		"material": s.material,
		"owned": Array(s.owned),
		"pressure": Dictionary(s.pressure),
		"expansion": Dictionary(s.expansion),
		"focus_id": s.focus_id,
	}


## The bots side of a snapshot: every bot, the fielded ids and the skill uses
## banked toward the next level.
static func squad_snapshot(squad: BotSquad, ledger: SkillUseLedger) -> Dictionary:
	var bots := []
	if squad != null:
		for bot in squad.bots:
			bots.append(bot_snapshot(bot))
	return {
		"bots": bots,
		"fielded": Array(squad.fielded_ids) if squad != null else [],
		"banked": Dictionary(ledger.banked) if ledger != null else {},
	}


## One bot: id, name, hp, stats, skills with levels, and every stored field
## of its personality (whatever the personality model holds).
static func bot_snapshot(bot: Bot) -> Dictionary:
	var stats := {}
	for stat in Bot.STAT_NAMES:
		stats[stat] = bot.stats.get(stat)
	var skills := []
	for skill in bot.skills:
		if skill != null:
			skills.append({"name": skill.display_name, "effect": skill.effect_id, "level": skill.level})
	return {
		"id": bot.id,
		"name": bot.display_name,
		"hp": bot.hp,
		"stats": stats,
		"skills": skills,
		"personality": stored_fields(bot.personality),
	}


## A Resource's own stored script fields, name -> value.
static func stored_fields(resource: Resource) -> Dictionary:
	var out := {}
	if resource == null:
		return out
	for prop in resource.get_property_list():
		var usage: int = prop.usage
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE and usage & PROPERTY_USAGE_STORAGE:
			out[prop.name] = resource.get(prop.name)
	return out


## Per bot, every field that differs between two squad snapshots' bots:
## {bot id: {"hp": [before, after], "skill:Strike": [1, 2],
## "personality:aggressive_defensive": [0.1, 0.2]}}. Bots with no change are
## left out.
static func bot_changes(before: Dictionary, after: Dictionary) -> Dictionary:
	var old := {}
	for b: Dictionary in before.get("bots", []):
		old[b.id] = _flat_bot(b)
	var out := {}
	for b: Dictionary in after.get("bots", []):
		var now := _flat_bot(b)
		var was: Dictionary = old.get(b.id, {})
		var changed := {}
		for key: String in now:
			if not was.has(key) or str(was[key]) != str(now[key]):
				changed[key] = [was.get(key), now[key]]
		if not changed.is_empty():
			out[b.id] = changed
	return out


static func _flat_bot(b: Dictionary) -> Dictionary:
	var flat := {"hp": b.get("hp")}
	for s: Dictionary in b.get("skills", []):
		flat["skill:%s" % s.name] = s.level
	var p: Dictionary = b.get("personality", {})
	for key: String in p:
		flat["personality:%s" % key] = p[key]
	return flat


# --- Fight data ---------------------------------------------------------------------

static func command_line(command: FightCommand, problem: String) -> Dictionary:
	return {
		"kind": KIND_COMMAND,
		"cmd": FightCommand.Kind.keys()[command.kind].to_lower(),
		"arg": command.arg,
		"ticks": command.ticks,
		"problem": problem,
	}


## The FightCommand a command line recorded, or null if it is not one.
static func command_from(line: Dictionary) -> FightCommand:
	var kind := FightCommand.Kind.keys().find(str(line.get("cmd", "")).to_upper())
	if kind < 0:
		return null
	var command := FightCommand.new(kind, str(line.get("arg", "")))
	command.ticks = int(line.get("ticks", 0))
	return command


static func event_dict(e: FightEvent) -> Dictionary:
	var d := {
		"kind": FightEvent.Kind.keys()[e.kind].to_lower(),
		"target": e.target_id,
		"skill": e.skill_id,
		"level": e.skill_level,
		"amount": e.amount,
	}
	if e.kind in [FightEvent.Kind.HIT, FightEvent.Kind.HEAL, FightEvent.Kind.DOWN]:
		d["hp"] = [e.hp_before, e.hp_after, e.max_hp]
	if e.kind == FightEvent.Kind.HIT and e.blocked_percent > 0:
		d["blocked"] = e.blocked_percent
	if e.kind in [FightEvent.Kind.SKILL, FightEvent.Kind.WAIT]:
		d["energy"] = [e.energy_before, e.energy_after]
	return d


static func resolved_line(fight: Fight, actor_id: String, tag: String) -> Dictionary:
	var actor := fight.combatant(actor_id)
	var events := []
	for e in fight.last_events:
		events.append(event_dict(e))
	return {
		"kind": KIND_RESOLVED,
		"index": fight.action_count,
		"actor": actor_id,
		"side": "player" if actor != null and actor.side == Combatant.Side.PLAYER else "enemy",
		"tag": tag,
		"events": events,
	}


# --- Comparing ----------------------------------------------------------------------

## `value` as it reads back from a journal line: through JSON and back, so
## numbers compare the same way on both sides.
static func normalize(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value, "", false, true))


## Every place `actual` differs from `expected`, as "path: expected X, got Y".
## Numbers match within `tolerance`, relative to their size (at least 1).
static func differences(expected: Variant, actual: Variant, tolerance := 0.000001, at := "") -> Array[String]:
	var out: Array[String] = []
	expected = normalize(expected)
	actual = normalize(actual)
	_diff(expected, actual, tolerance, at, out)
	return out


static func _diff(a: Variant, b: Variant, tolerance: float, at: String, out: Array[String]) -> void:
	var a_number := typeof(a) in [TYPE_INT, TYPE_FLOAT]
	var b_number := typeof(b) in [TYPE_INT, TYPE_FLOAT]
	if a_number and b_number:
		if absf(float(a) - float(b)) > tolerance * maxf(1.0, maxf(absf(float(a)), absf(float(b)))):
			out.append("%s: expected %s, got %s" % [at, a, b])
		return
	if a is Dictionary and b is Dictionary:
		var keys := {}
		for k: Variant in a:
			keys[k] = true
		for k: Variant in b:
			keys[k] = true
		var sorted := keys.keys()
		sorted.sort()
		for k: Variant in sorted:
			var sub := "%s.%s" % [at, k] if not at.is_empty() else str(k)
			if not a.has(k):
				out.append("%s: not expected, got %s" % [sub, b[k]])
			elif not b.has(k):
				out.append("%s: expected %s, missing" % [sub, a[k]])
			else:
				_diff(a[k], b[k], tolerance, sub, out)
		return
	if a is Array and b is Array:
		if a.size() != b.size():
			out.append("%s: expected %d items %s, got %d items %s" % [at, a.size(), a, b.size(), b])
			return
		for i in a.size():
			_diff(a[i], b[i], tolerance, "%s[%d]" % [at, i], out)
		return
	if typeof(a) != typeof(b) or a != b:
		out.append("%s: expected %s, got %s" % [at, a, b])
