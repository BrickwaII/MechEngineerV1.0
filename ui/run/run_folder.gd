class_name RunFolder
extends RefCounted
## One folder per run under the runs folder (data/run/run_data.json,
## user://runs by default):
##
##   user://runs/<yyyy-mm-dd_hhmm>_<seed>/
##       run.res        the save (RunSave)
##       journal.jsonl  the run journal (tools/run_journal.gd)
##       summary.json   the one-line summary the load list shows
##       reports/       F8 feedback reports, one folder each
##
## A new run never reuses a folder: a second run with the same seed in the
## same minute gets "_2", and so on. Finished runs, won or lost, keep their
## folder and summary.
##
## Where user:// is on disk: see ui/run/README.md (Windows:
## %APPDATA%\Godot\app_userdata\Mech Engineer, macOS:
## ~/Library/Application Support/Godot/app_userdata/Mech Engineer).

const SAVE_FILE := "run.res"
const SUMMARY_FILE := "summary.json"
const REPORTS_DIR := "reports"
## In the runs folder: says the old single-slot save was offered once.
const LEGACY_MARKER := "legacy_import.json"
const SUMMARY_VERSION := 1


## Makes a new, empty run folder for `seed` under `root` and returns its path.
## `when` is a Time datetime dictionary; empty means now. Returns "" if the
## folder cannot be made.
static func create(root: String, seed_value: int, when: Dictionary = {}) -> String:
	if when.is_empty():
		when = Time.get_datetime_dict_from_system()
	var base := root.path_join(name_for(seed_value, when))
	var path := base
	var n := 1
	while DirAccess.dir_exists_absolute(path):
		n += 1
		path = "%s_%d" % [base, n]
	if DirAccess.make_dir_recursive_absolute(path.path_join(REPORTS_DIR)) != OK:
		return ""
	return path


## "2026-10-11_1403_123456".
static func name_for(seed_value: int, when: Dictionary) -> String:
	return "%04d-%02d-%02d_%02d%02d_%d" % [
		int(when.get("year", 0)), int(when.get("month", 0)), int(when.get("day", 0)),
		int(when.get("hour", 0)), int(when.get("minute", 0)), seed_value]


static func save_path(dir: String) -> String:
	return dir.path_join(SAVE_FILE)


static func journal_path(dir: String) -> String:
	return dir.path_join(RunJournal.FILE_NAME)


static func summary_path(dir: String) -> String:
	return dir.path_join(SUMMARY_FILE)


static func reports_path(dir: String) -> String:
	return dir.path_join(REPORTS_DIR)


## The folder's summary, or {} when it has none.
static func read_summary(dir: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(summary_path(dir)))
	return parsed if parsed is Dictionary else {}


static func write_summary(dir: String, summary: Dictionary) -> Error:
	var file := FileAccess.open(summary_path(dir), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(summary, "\t", false, true))
	file.close()
	return OK


## A fresh summary for a new run.
static func new_summary(seed_value: int, dir: String) -> Dictionary:
	var now := Time.get_unix_time_from_system()
	return {
		"version": SUMMARY_VERSION,
		"folder": dir.get_file(),
		"seed": seed_value,
		"created": Time.get_datetime_string_from_system(false, true),
		"updated_unix": now,
		"stage": "draft",
		"act": 1,
		"act_name": "",
		"day": 1,
		"regions_held": 0,
		"regions_total": 0,
		"fights_won": 0,
		"fights_lost": 0,
		"finished": false,
		"won": false,
		"play_s": 0.0,
		"imported": false,
	}


## Every run folder under `root` that has a summary, newest first, each
## summary with "dir" (its path) and "has_save" added. At most `limit`.
static func list(root: String, limit := 100) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(root):
		return out
	for name in DirAccess.get_directories_at(root):
		var dir := root.path_join(name)
		var summary := read_summary(dir)
		if summary.is_empty():
			continue
		summary["dir"] = dir
		summary["has_save"] = FileAccess.file_exists(save_path(dir))
		out.append(summary)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("updated_unix", 0)) > float(b.get("updated_unix", 0)))
	return out.slice(0, limit)


## True when the run can be played on: it has a save and has not ended.
static func can_continue(summary: Dictionary) -> bool:
	return bool(summary.get("has_save", false)) and not bool(summary.get("finished", false))


## The folder of the most recently played run that can be continued, or "".
static func latest_continuable(root: String) -> String:
	for summary in list(root):
		if can_continue(summary):
			return summary.dir
	return ""


## One line for the load list: "Act 2 · Day 14 · 9/22 regions · 5 won 2 lost · in progress".
static func describe(summary: Dictionary) -> String:
	var parts := PackedStringArray()
	if str(summary.get("stage", "")) == "draft":
		parts.append("Draft")
	else:
		parts.append("Act %d" % int(summary.get("act", 1)))
		parts.append("Day %d" % int(summary.get("day", 1)))
		parts.append("%d/%d regions" % [int(summary.get("regions_held", 0)), int(summary.get("regions_total", 0))])
	parts.append("%d won %d lost" % [int(summary.get("fights_won", 0)), int(summary.get("fights_lost", 0))])
	parts.append(play_time_text(float(summary.get("play_s", 0.0))))
	if bool(summary.get("finished", false)):
		parts.append("won" if bool(summary.get("won", false)) else "lost")
	else:
		parts.append("in progress")
	if bool(summary.get("imported", false)):
		parts.append("imported")
	return " · ".join(parts)


## "1h 04m", "12m 30s".
static func play_time_text(seconds: float) -> String:
	var s := int(seconds)
	if s >= 3600:
		return "%dh %02dm" % [s / 3600, (s % 3600) / 60]
	return "%dm %02ds" % [s / 60, s % 60]


# --- The old single-slot save ---------------------------------------------------

## True when `legacy_path` holds a usable save that has not been offered yet.
static func legacy_pending(root: String, legacy_path: String) -> bool:
	return (not FileAccess.file_exists(root.path_join(LEGACY_MARKER))
		and RunSave.load_file(legacy_path) != null)


## Remembers that the old save was offered, so it is offered only once.
static func mark_legacy_offered(root: String, imported_dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(root)
	var file := FileAccess.open(root.path_join(LEGACY_MARKER), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"imported": imported_dir}))
		file.close()


## Copies the old save into a run folder of its own, with a summary, and
## marks it offered. The old file is left where it was. Returns the folder,
## or "" if the save does not load.
static func import_legacy(root: String, legacy_path: String, acts_file := "res://data/tuning/acts.json") -> String:
	var save := RunSave.load_file(legacy_path)
	if save == null:
		return ""
	var when := Time.get_datetime_dict_from_unix_time(FileAccess.get_modified_time(legacy_path))
	var dir := create(root, save.run_seed, when)
	if dir.is_empty() or save.save_file(save_path(dir)) != OK:
		return ""
	var summary := new_summary(save.run_seed, dir)
	var state := save.run_state()
	summary.stage = "map"
	summary.imported = true
	summary.act = state.act + 1
	summary.regions_held = state.owned.size()
	var plan := ActPlan.load_file(acts_file)
	if plan.is_valid() and state.act < plan.act_count() and plan.choose_variant(state.act, state.region_set_id):
		summary.act_name = plan.act_name(state.act)
		var tuning := plan.load_tuning(state.act)
		if tuning.points_per_day > 0:
			summary.day = mini(tuning.total_points / tuning.points_per_day, state.time_points / tuning.points_per_day + 1)
		summary.regions_total = plan.load_map(state.act).regions.size()
	write_summary(dir, summary)
	mark_legacy_offered(root, dir)
	return dir
