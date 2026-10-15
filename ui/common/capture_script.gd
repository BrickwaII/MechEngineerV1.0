class_name CaptureScript
extends SceneTree
## The base of the screenshot scripts (ui/**/capture_*.gd): the command line,
## waiting on frames, saving the view as PNGs, and the steps several scripts
## take to drive a run or a battle. A script calls start() from _init() and
## puts its shots in _run():
##
##   extends CaptureScript
##   func _init() -> void:
##       start("user://capture_out")
##   func _run() -> void:
##       ...
##       await save("main_menu")
##       quit()
##
## Run one under a display:
##     xvfb-run -a -s "-screen 0 1600x1000x24" godot --path . --rendering-driver opengl3 \
##         --resolution 1280x820 -s res://ui/<folder>/capture_<name>.gd -- <out_dir> [id ...]

## Where the PNGs go: the first command line argument, else the script's default.
var out_dir := ""
## The ids after <out_dir> on the command line, for scripts that take them.
var only: PackedStringArray = []


## Reads `<out_dir> [id ...]` from the command line, makes the folder and
## runs _run() once the tree is up. With `takes_ids`, the ids go to `only`,
## or `default_ids` when none are given.
func start(default_dir: String, takes_ids := false, default_ids: Array[String] = []) -> void:
	out_dir = default_dir
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
		if takes_ids:
			only = args.slice(1)
	if takes_ids and only.is_empty():
		only = PackedStringArray(default_ids)
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


## The script's shots. Call quit() at the end.
func _run() -> void:
	quit()


func frames(n: int) -> void:
	for i in n:
		await process_frame


## Waits until `done` returns true, at most `max_frames` frames (no limit
## when negative).
func wait_until(done: Callable, max_frames := 3000) -> void:
	var guard := 0
	while not done.call() and (max_frames < 0 or guard < max_frames):
		guard += 1
		await process_frame


## The view once this frame is drawn, cut to `crop` when it has a size.
func grab(crop := Rect2i()) -> Image:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	return image if crop.size == Vector2i.ZERO else image.get_region(crop.intersection(Rect2i(Vector2i.ZERO, image.get_size())))


## Saves the view (cut to `crop` when it has a size) as <out_dir>/<file>.png.
func save(file: String, crop := Rect2i()) -> void:
	var image := await grab(crop)
	image.save_png(out_dir.path_join(file + ".png"))
	print("saved ", file)


## Saves `shots` side by side, `per_row` to a row, as one PNG.
func save_strip(file: String, shots: Array[Image], per_row := 4) -> void:
	var w := shots[0].get_width()
	var h := shots[0].get_height()
	var rows := ceili(shots.size() / float(per_row))
	var gap := 4
	var strip := Image.create(per_row * w + (per_row - 1) * gap, rows * h + (rows - 1) * gap, false, Image.FORMAT_RGBA8)
	strip.fill(Color("#05090e"))
	for i in shots.size():
		var shot := shots[i]
		shot.convert(Image.FORMAT_RGBA8)
		@warning_ignore("integer_division")
		strip.blit_rect(shot, Rect2i(Vector2i.ZERO, shot.get_size()), Vector2i((i % per_row) * (w + gap), (i / per_row) * (h + gap)))
	strip.save_png(out_dir.path_join(file + ".png"))
	print("saved ", file)


## Waits until the battle waits on the player (or ends), presentation done.
func until_player_turn(screen: BattleScreen) -> void:
	var guard := 0
	while (not screen.handler.is_player_turn() or screen.presenter.is_busy()) and guard < 2000 and not screen.fight.is_over():
		await process_frame
		guard += 1


## Plays the pending bot's turn: its strongest damage skill that can be used
## on a target, else a wait.
static func take_turn(battle: BattleScreen) -> void:
	var actor := battle.handler.actor()
	var skills := actor.skills()
	skills.reverse()
	for skill in skills:
		if not skill.is_damage() or not battle.handler.skill_problem(skill.id).is_empty():
			continue
		battle.send(FightCommand.select_skill(skill.id))
		if not battle.handler.is_choosing_target():
			return
		for enemy in battle.fight.opponents_of(actor):
			if battle.handler.target_problem(enemy.id).is_empty():
				battle.send(FightCommand.select_target(enemy.id))
				return
		battle.send(FightCommand.cancel())
	battle.send(FightCommand.wait())


## The in-range region with the lowest defense, file order on a tie, or "".
static func weakest(c: Campaign) -> String:
	var best: MapRegion = null
	for region in c.map.regions:
		if c.standing(region.id) == Campaign.Standing.IN_RANGE and (best == null or region.defense < best.defense):
			best = region
	return best.id if best != null else ""


## Deletes `path` and everything in it.
static func remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	for dir in DirAccess.get_directories_at(path):
		remove_tree(path.path_join(dir))
	DirAccess.remove_absolute(path)
