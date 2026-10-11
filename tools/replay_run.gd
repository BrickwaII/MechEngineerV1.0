extends SceneTree
## Re-plays a run from its journal, headless, and prints its timeline:
##
##   godot --headless --path . -s res://tools/replay_run.gd -- <run> [--detail] [--no-replay]
##
## <run> is a run folder (it reads journal.jsonl inside) or a journal file;
## a path on disk or a user:// path. --detail lists every battle command and
## resolved action; --no-replay only prints the timeline. Exits 0 when every
## snapshot matched, 1 on a mismatch (a determinism bug: report it), 2 when
## the journal cannot be read.


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var path := ""
	var detail := false
	var replay := true
	for arg in args:
		if arg == "--detail":
			detail = true
		elif arg == "--no-replay":
			replay = false
		else:
			path = arg
	if path.is_empty():
		printerr("usage: -s res://tools/replay_run.gd -- <run folder or journal.jsonl> [--detail] [--no-replay]")
		quit(2)
		return
	if DirAccess.dir_exists_absolute(path):
		path = path.path_join(RunJournal.FILE_NAME)
	var journal := RunJournal.read_file(path)
	if journal.is_empty():
		printerr("no journal lines in %s" % path)
		quit(2)
		return
	for text in RunTimeline.lines(journal, detail):
		print(text)
	if not replay:
		quit(0)
		return
	var r := RunReplay.new(journal)
	await r.run()
	print("")
	if r.is_match():
		print("REPLAY OK: %d lines, %d fights, %d snapshots matched." % [journal.size(), r.fights_played, r.snapshots_checked])
		quit(0)
		return
	print("REPLAY MISMATCH: %d differences (%d fights, %d snapshots checked). Fights are deterministic: this is a bug." % [
		r.mismatches.size(), r.fights_played, r.snapshots_checked])
	for m in r.mismatches.slice(0, 40):
		print("  " + m)
	quit(1)
