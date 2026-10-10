extends SceneTree
## Renders the demo screens to PNGs for pull requests. Needs a display:
##     xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1280x820 \
##         -s res://ui/common/demo/capture_screenshots.gd -- <out_dir>
## Writes theme_demo.png, sprite_demo.png, settings_screen.png and
## feel_frame_NN_<ms>.png (a big hit, frame by frame) into <out_dir>.

const FEEL_FRAME_TIMES_MS := [0, 40, 90, 140, 220, 320, 450, 600, 800]
const FEEL_CROP := Rect2i(90, 150, 760, 285)

var out_dir := "res://ui/common/screenshots"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	var theme_demo: Control = load("res://ui/common/demo/theme_demo.tscn").instantiate()
	root.add_child(theme_demo)
	await _settle(10)
	await _save("theme_demo")

	var settings := GameSettings.new()
	var screen := SettingsScreen.open_overlay(root, settings)
	await _settle(10)
	await _save("settings_screen")
	screen.closed.emit()
	theme_demo.queue_free()
	await _settle(4)

	var sprite_demo: Control = load("res://ui/common/demo/sprite_demo.tscn").instantiate()
	root.add_child(sprite_demo)
	await _settle(6)
	sprite_demo.freeze_on(0.5)
	await _settle(4)
	await _save("sprite_demo")
	sprite_demo.queue_free()
	await _settle(4)

	var feel_demo: Control = load("res://ui/common/demo/feel_demo.tscn").instantiate()
	root.add_child(feel_demo)
	await _settle(20)
	var start := Time.get_ticks_msec()
	var index := 0
	for ms: int in FEEL_FRAME_TIMES_MS:
		while Time.get_ticks_msec() - start < ms:
			await process_frame
		if ms == 0:
			await _save_crop("feel_frame_%02d_%04d" % [index, ms])
			start = Time.get_ticks_msec()
			feel_demo._land_hit(30, true)
		else:
			await _save_crop("feel_frame_%02d_%04d" % [index, ms])
		index += 1
	quit()


func _settle(frames: int) -> void:
	for i in frames:
		await process_frame


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)


func _save_crop(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image().get_region(FEEL_CROP)
	image.save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)
