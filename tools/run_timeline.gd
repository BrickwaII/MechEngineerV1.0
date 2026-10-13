class_name RunTimeline
extends RefCounted
## A readable timeline of a run from its journal (RunJournal), one line per
## step: real play time, act and day, what the player did, how each fight
## went and what the bots learned from it, and a summary per act with its
## real-time length against the act target (data/run/run_data.json).
##
##   for text in RunTimeline.lines(RunJournal.read_file(path)):
##       print(text)
##
## `detail` adds every battle command and resolved action.


static func lines(journal: Array[Dictionary], detail := false, settings: RunDataSettings = null) -> PackedStringArray:
	if settings == null:
		settings = RunDataSettings.load_default()
	var t := _Timeline.new(settings, detail)
	for line in journal:
		t.add(line)
	t.close()
	return t.out


## "12:05" for under an hour, "1:02:05" past it.
static func clock_text(seconds: float) -> String:
	var s := maxi(0, int(seconds))
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s % 3600) / 60, s % 60]
	return "%02d:%02d" % [s / 60, s % 60]


## "1m 20s".
static func span_text(seconds: float) -> String:
	var s := maxi(0, int(round(seconds)))
	if s >= 3600:
		return "%dh %02dm" % [s / 3600, (s % 3600) / 60]
	return "%dm %02ds" % [s / 60, s % 60]


class _Timeline:
	var out := PackedStringArray()
	var settings: RunDataSettings
	var detail := false
	var names := {}
	var act := -1
	var act_start_s := 0.0
	var act_first_day := 1
	var act_won := 0
	var act_lost := 0
	var last_line: Dictionary = {}
	var held := 0
	var total := 0
	var fight_line := ""
	var commands := 0
	var refused := 0
	var ended := false

	func _init(p_settings: RunDataSettings, p_detail: bool) -> void:
		settings = p_settings
		detail = p_detail

	func add(line: Dictionary) -> void:
		var kind := str(line.get("kind", ""))
		var play := float(line.get("play_s", 0.0))
		var stamp := RunTimeline.clock_text(play)
		var where := "A%d D%-3d" % [int(line.get("act", 0)) + 1, int(line.get("day", 1))] if line.has("act") else "       "
		match kind:
			RunJournal.KIND_RUN_START:
				var variants: Dictionary = line.get("variants", {})
				var v := ", ".join(variants.keys().map(func(k: Variant) -> String: return "%s=%s" % [k, variants[k]]))
				out.append("RUN seed %d · started %s · squad %d of %d · variants: %s" % [
					int(line.get("seed", 0)), str(line.get("ts", "")).left(16), int(line.get("squad_size", 0)),
					int(line.get("draft_size", 0)), v if not v.is_empty() else "defaults"])
			RunJournal.KIND_SESSION:
				out.append("%s  %s session %s (%s)" % [stamp, where, line.get("event"), str(line.get("ts", "")).left(16)])
			RunJournal.KIND_DRAFT_OPEN:
				for b: Dictionary in line.get("offered", []):
					names[b.id] = b.name
			RunJournal.KIND_DRAFT_DONE:
				var picked: Array = line.get("picks", []).map(func(id: Variant) -> String: return str(names.get(id, id)))
				out.append("%s  DRAFT   picked %s (%s)" % [stamp, ", ".join(picked), RunTimeline.span_text(float(line.get("seconds", 0.0)))])
			RunJournal.KIND_MAP_START:
				out.append("%s  %s start at %s" % [stamp, where, line.get("start_id")])
			RunJournal.KIND_SNAPSHOT:
				_snapshot(line, stamp, where)
			RunJournal.KIND_ACTION:
				_action(line, stamp, where)
			RunJournal.KIND_FIGHT_START:
				commands = 0
				refused = 0
				fight_line = "%s  %s   fight %d: %s %s (level %d, seed %d)" % [stamp, where, int(line.get("fight", 0)),
					line.get("fight_kind"), line.get("territory_name", line.get("territory")), int(line.get("level", 0)),
					int(line.get("seed", 0))]
				if detail:
					out.append(fight_line)
			RunJournal.KIND_COMMAND:
				commands += 1
				if not str(line.get("problem", "")).is_empty():
					refused += 1
				if detail:
					out.append("%s             > %s %s%s" % [stamp, line.get("cmd"), line.get("arg"),
						"" if str(line.get("problem", "")).is_empty() else "  (refused: %s)" % line.problem])
			RunJournal.KIND_RESOLVED:
				if detail:
					out.append("%s             = #%d %s %s%s" % [stamp, int(line.get("index", 0)), line.get("side"), line.get("tag"), _events_text(line)])
			RunJournal.KIND_FIGHT_END:
				if str(line.get("outcome")) == RunJournal.OUTCOME_ABANDONED:
					out.append("%s  %s   -> ABANDONED (left for the main menu), %d actions, %d commands" % [
						stamp, where, int(line.get("actions", -1)), commands])
					last_line = line
					return
				var won := str(line.get("outcome")) == "victory"
				act_won += 1 if won else 0
				act_lost += 0 if won else 1
				out.append("%s  %s   -> %s, %d actions, %s real, %d commands (%d refused), grid -%s" % [
					stamp, where, str(line.get("outcome")).to_upper(), int(line.get("actions", -1)),
					RunTimeline.span_text(float(line.get("seconds", 0.0))), commands, refused,
					snappedf(float(line.get("grid_cost", 0.0)), 0.1)])
			RunJournal.KIND_POST_FIGHT:
				var changes: Dictionary = line.get("changes", {})
				for bot_id: Variant in changes:
					var text := _changes_text(changes[bot_id])
					if not text.is_empty():
						out.append("%s             %s: %s" % [stamp, names.get(bot_id, bot_id), text])
			RunJournal.KIND_EXPANDED:
				out.append("%s  %s   %s went over to your side" % [stamp, where, line.get("region_name", line.get("region"))])
			RunJournal.KIND_ESCALATION:
				out.append("%s  %s   NEWS (%s): %s" % [stamp, where, line.get("tier_name"), line.get("headline")])
			RunJournal.KIND_FEEDBACK:
				out.append("%s  %s F8 report: %s, mood %d (%s)" % [stamp, where, line.get("category"), int(line.get("rating", 0)), line.get("folder")])
			RunJournal.KIND_RUN_END:
				_close_act(line)
				ended = true
				out.append("%s  END     %s: %s · %s played" % [stamp, "WON" if line.get("won") else "LOST",
					line.get("reason"), RunTimeline.span_text(play)])
		last_line = line

	func close() -> void:
		if not ended and not last_line.is_empty():
			_close_act(last_line)
			out.append("%s  (run in progress · %s played)" % [RunTimeline.clock_text(float(last_line.get("play_s", 0.0))),
				RunTimeline.span_text(float(last_line.get("play_s", 0.0)))])

	func _snapshot(line: Dictionary, stamp: String, where: String) -> void:
		var state: Dictionary = line.get("state", {})
		held = (state.get("owned", []) as Array).size()
		total = int(line.get("regions_total", total))
		var reason := str(line.get("reason"))
		if reason in [RunJournal.SNAPSHOT_RUN_START, RunJournal.SNAPSHOT_ACT, RunJournal.SNAPSHOT_LOAD]:
			if int(state.get("act", 0)) != act:
				act = int(state.get("act", 0))
				act_start_s = float(line.get("play_s", 0.0))
				act_first_day = int(state.get("day", 1))
				act_won = 0
				act_lost = 0
				out.append("── ACT %d (%s) ──" % [act + 1, state.get("region_set_id", "")])
		if reason != RunJournal.SNAPSHOT_FIGHT or detail:
			out.append("%s  %s   [%s] holds %d/%d · grid %s · energy %s · material %s" % [stamp, where, reason, held, total,
				snappedf(float(state.get("grid", 0.0)), 0.1), snappedf(float(state.get("energy", 0.0)), 0.1),
				snappedf(float(state.get("material", 0.0)), 0.1)])

	func _action(line: Dictionary, stamp: String, where: String) -> void:
		var name := str(line.get("action"))
		match name:
			RunJournal.ACTION_ACT_ZOOM:
				_close_act(line)
				out.append("%s  %s   act zoom" % [stamp, where])
			RunJournal.ACTION_EXIT:
				out.append("%s  %s   left for the main menu (from the %s%s)" % [stamp, where,
					str(line.get("screen", "map")).replace("_", " "), ", mid-battle" if line.get("mid_battle", false) else ""])
			RunJournal.ACTION_SAVE:
				if detail or not bool(line.get("auto", false)):
					out.append("%s  %s   %s" % [stamp, where, "autosave" if line.get("auto", false) else "save"])
			_:
				var region := str(line.get("region_name", line.get("region", "")))
				out.append("%s  %s   %s%s" % [stamp, where, name, "" if region.is_empty() else " " + region])

	func _close_act(line: Dictionary) -> void:
		if act < 0:
			return
		var minutes := (float(line.get("play_s", 0.0)) - act_start_s) / 60.0
		var target := settings.act_target_minutes
		var verdict := "on target" if minutes >= target.x and minutes <= target.y else (
			"SHORT" if minutes < target.x else "LONG")
		out.append("── ACT %d done: %s real (target %d-%d min: %s) · days %d-%d · holds %d/%d · fights %d won %d lost ──" % [
			act + 1, RunTimeline.span_text(minutes * 60.0), target.x, target.y, verdict, act_first_day,
			int(line.get("day", act_first_day)), held, total, act_won, act_lost])
		act = -1

	func _events_text(line: Dictionary) -> String:
		var parts := PackedStringArray()
		for e: Dictionary in line.get("events", []):
			if e.kind in ["hit", "heal"]:
				parts.append("%s %s %d" % [e.kind, e.target, int(e.amount)])
			elif e.kind == "down":
				parts.append("%s down" % e.target)
		return "" if parts.is_empty() else ": " + ", ".join(parts)

	func _changes_text(changed: Dictionary) -> String:
		var parts := PackedStringArray()
		for key: String in changed:
			var pair: Array = changed[key]
			if key.begins_with("skill:"):
				parts.append("%s level %d→%d" % [key.trim_prefix("skill:"), int(pair[0]), int(pair[1])])
			elif key.begins_with("banked:"):
				parts.append("%s %+d uses" % [key.trim_prefix("banked:"), int(pair[1]) - int(pair[0])])
			elif key.begins_with("personality:") and pair[0] is float and pair[1] is float:
				parts.append("%s %+.3f" % [key.trim_prefix("personality:"), float(pair[1]) - float(pair[0])])
		return ", ".join(parts)
