extends SceneTree
## Renders the M7 P3 screens to PNGs for pull requests. Needs a display:
##     xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1280x820 \
##         -s res://ui/run/demo/capture_screenshots.gd -- <out_dir> [shots]
## shots is a comma list of: acts, capture, zoom, draft, readout, transition
## (all by default). Frame strips are one PNG of frames side by side.

const OVERWORLD := "res://ui/overworld/overworld.tscn"

var out_dir := "res://ui/run/screenshots"
var shots := PackedStringArray(["acts", "capture", "zoom", "draft", "readout", "transition"])


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		shots = args[1].split(",")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	for shot in shots:
		await call("_shot_" + shot)
		await _settle(4)
	quit()


# --- Acts with hover and selection -------------------------------------------------

func _shot_acts() -> void:
	var screen: Control = load(OVERWORLD).instantiate()
	screen.start_picker = func(options: Array) -> String: return options[0].id
	root.add_child(screen)
	await _settle(6)
	await _hover_and_select(screen, "act1_hover_select", "north_seattle", "bothell")
	screen.campaign.state.time_points = screen.campaign.tuning.total_points - 1
	screen._on_wait()
	screen.zoom_out()
	await _wait_until(func() -> bool: return not screen.zooming)
	await _settle(30)
	await _hover_and_select(screen, "act2_hover_select", "oregon", "idaho")
	screen.campaign.state.time_points = screen.campaign.tuning.total_points - 1
	screen._on_wait()
	screen.zoom_out()
	await _wait_until(func() -> bool: return not screen.zooming)
	await _settle(30)
	await _hover_and_select(screen, "act3_hover_select", "canada", "mexico")
	screen.queue_free()


func _hover_and_select(screen: Control, name: String, select_id: String, hover_id: String) -> void:
	var view: Control = screen.map_view
	if not screen.campaign.map.has_region(select_id):
		select_id = _first_hostile(screen)
	if not screen.campaign.map.has_region(hover_id):
		hover_id = _first_hostile(screen, select_id)
	view.select(select_id)
	view._hover_at(view.label_position(hover_id))
	await _settle(30)
	await _save(name)


func _first_hostile(screen: Control, other := "") -> String:
	for region in screen.campaign.map.regions:
		if screen.campaign.standing(region.id) == Campaign.Standing.IN_RANGE and region.id != other:
			return region.id
	return ""


# --- Helpers -----------------------------------------------------------------------

func _wait_until(done: Callable) -> void:
	while not done.call():
		await process_frame


func _settle(frames: int) -> void:
	for i in frames:
		await process_frame


func _grab(crop := Rect2i()) -> Image:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	return image if crop.size == Vector2i.ZERO else image.get_region(crop)


func _save(name: String, crop := Rect2i()) -> void:
	var image := await _grab(crop)
	image.save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)


## Frames side by side (wrapping after `per_row`), each labelled with its time.
func _save_strip(name: String, frames: Array[Image], per_row := 4) -> void:
	var w := frames[0].get_width()
	var h := frames[0].get_height()
	var rows := ceili(frames.size() / float(per_row))
	var gap := 4
	var strip := Image.create(per_row * w + (per_row - 1) * gap, rows * h + (rows - 1) * gap, false, Image.FORMAT_RGBA8)
	strip.fill(Color("#05090e"))
	for i in frames.size():
		var frame := frames[i]
		frame.convert(Image.FORMAT_RGBA8)
		strip.blit_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), Vector2i((i % per_row) * (w + gap), (i / per_row) * (h + gap)))
	strip.save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)
