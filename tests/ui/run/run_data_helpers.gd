extends RefCounted
## Shared by the run tests: a scratch runs folder per suite, removed after
## each test, and the steps that drive a RunFlow the way its screens do.


## Deletes `path` and everything in it.
static func remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		return
	for name in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(name))
	for name in DirAccess.get_directories_at(path):
		remove_tree(path.path_join(name))
	DirAccess.remove_absolute(path)


## The only run folder under `root`, or "" when there is not exactly one.
static func only_run(root: String) -> String:
	var dirs := DirAccess.get_directories_at(root)
	return root.path_join(dirs[0]) if dirs.size() == 1 else ""


## Waits `n` frames of `flow`'s tree.
static func frames(flow: Node, n: int) -> void:
	for i in n:
		await flow.get_tree().process_frame


## Picks the first squad_size bots of the draft, as clicking their cards does,
## and deploys them.
static func draft(flow: RunFlow) -> void:
	var screen := flow.draft_screen
	for i in screen.picker.squad_size():
		screen.cards[screen.picker.bots()[i].id].pressed.emit()
	screen.start_button.pressed.emit()
	await frames(flow, 1)


## The weakest hostile region next to the network.
static func adjacent_target(flow: RunFlow) -> String:
	var campaign: Campaign = flow.overworld.campaign
	var best: MapRegion = null
	for region in campaign.map.regions:
		if campaign.standing(region.id) == Campaign.Standing.IN_RANGE and (best == null or region.defense < best.defense):
			best = region
	return best.id


## Waits until `flow` reaches `stage`, at most `max_frames` frames.
static func await_stage(flow: RunFlow, stage: RunFlow.Stage, max_frames := 60) -> void:
	var guard := 0
	while flow.stage != stage and guard < max_frames:
		await frames(flow, 1)
		guard += 1


## The run's journal lines so far.
static func journal(flow: RunFlow) -> Array[Dictionary]:
	return RunJournal.read_file(RunFolder.journal_path(flow.run_dir))
