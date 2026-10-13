class_name RunDataSettings
extends RefCounted
## Settings for run data (run folders, the journal, the replay, the F8
## report), read from data/run/run_data.json.

const DEFAULT_PATH := "res://data/run/run_data.json"

## Where run folders live, one per run.
var runs_folder := "user://runs"
## The single-slot save from before run folders, offered once as an import.
var legacy_save := "user://run.res"
var autosave_at_map_start := true
var autosave_before_fight := true
var autosave_after_fight := true
var autosave_after_act := true
var feedback_categories: PackedStringArray = []
var mood_min := 1
var mood_max := 5
var mood_default := 3
var note_max_chars := 4000
## The most runs the load list shows, newest first.
var load_list_max := 100
## Two journal numbers match when they differ by at most this, relatively.
var replay_float_tolerance := 0.000001
## The real minutes one act should take, [low, high]. The timeline flags acts
## outside it.
var act_target_minutes := Vector2(10, 30)
var errors: Array[String] = []


static func load_default() -> RunDataSettings:
	return load_file(DEFAULT_PATH)


static func load_file(path: String) -> RunDataSettings:
	var s := RunDataSettings.new()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		s.errors.append("%s: not a JSON object" % path)
		return s
	var d: Dictionary = parsed
	s.runs_folder = str(d.get("runs_folder", s.runs_folder))
	s.legacy_save = str(d.get("legacy_save", s.legacy_save))
	var autosave: Dictionary = d.get("autosave", {})
	s.autosave_at_map_start = bool(autosave.get("at_map_start", true))
	s.autosave_before_fight = bool(autosave.get("before_fight", true))
	s.autosave_after_fight = bool(autosave.get("after_fight", true))
	s.autosave_after_act = bool(autosave.get("after_act", true))
	var feedback: Dictionary = d.get("feedback", {})
	s.feedback_categories = PackedStringArray(feedback.get("categories", ["other"]))
	s.mood_min = int(feedback.get("mood_min", s.mood_min))
	s.mood_max = int(feedback.get("mood_max", s.mood_max))
	s.mood_default = clampi(int(feedback.get("mood_default", s.mood_default)), s.mood_min, s.mood_max)
	s.note_max_chars = int(feedback.get("note_max_chars", s.note_max_chars))
	s.load_list_max = int(d.get("load_list_max", s.load_list_max))
	s.replay_float_tolerance = float(d.get("replay_float_tolerance", s.replay_float_tolerance))
	var target: Array = d.get("act_target_minutes", [10, 30])
	if target.size() == 2:
		s.act_target_minutes = Vector2(float(target[0]), float(target[1]))
	if s.feedback_categories.is_empty():
		s.errors.append("feedback.categories is empty")
	if s.mood_min > s.mood_max:
		s.errors.append("feedback.mood_min is above mood_max")
	return s


func is_valid() -> bool:
	return errors.is_empty()
