class_name FeedbackReport
extends RefCounted
## Writes one F8 feedback report into a run's reports/ folder:
##
##   reports/<yyyy-mm-dd_hhmmss>/
##       screenshot.png  the screen when F8 was pressed
##       note.json       note, category, rating, stage, act, day, screen,
##                       active variant choices, time
##       run.res         a copy of the run's save, if it has one
##       journal.jsonl   a copy of the journal so far
##
## Saving never touches another report: a second one in the same second gets
## "_2".

const NOTE_FILE := "note.json"
const SCREENSHOT_FILE := "screenshot.png"


## Writes the report and returns its folder, or "" if the folder cannot be
## made. `image` may be null (no screenshot, as in headless runs).
static func write(reports_dir: String, note: Dictionary, image: Image, save_src: String,
		journal_src: String, when: Dictionary = {}) -> String:
	if when.is_empty():
		when = Time.get_datetime_dict_from_system()
	var base := reports_dir.path_join("%04d-%02d-%02d_%02d%02d%02d" % [
		when.year, when.month, when.day, when.hour, when.minute, when.second])
	var dir := base
	var n := 1
	while DirAccess.dir_exists_absolute(dir):
		n += 1
		dir = "%s_%d" % [base, n]
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		return ""
	if image != null and not image.is_empty():
		image.save_png(dir.path_join(SCREENSHOT_FILE))
	JsonFile.write(dir.path_join(NOTE_FILE), note, "\t", false)
	if FileAccess.file_exists(save_src):
		DirAccess.copy_absolute(save_src, dir.path_join(save_src.get_file()))
	if FileAccess.file_exists(journal_src):
		DirAccess.copy_absolute(journal_src, dir.path_join(journal_src.get_file()))
	return dir
