extends CaptureScript
## Renders the demo screens to PNGs for pull requests. Needs a display:
##     xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1280x820 \
##         -s res://ui/common/demo/capture_screenshots.gd -- <out_dir>
## Writes theme_demo.png, sprite_demo.png, settings_screen.png and
## feel_frame_NN_<ms>.png (a big hit, frame by frame) into <out_dir>.

const FEEL_FRAME_TIMES_MS := [0, 40, 90, 140, 220, 320, 450, 600, 800]
const FEEL_CROP := Rect2i(90, 150, 760, 285)


func _init() -> void:
	start("res://ui/common/screenshots")


func _run() -> void:
	var theme_demo: Control = load("res://ui/common/demo/theme_demo.tscn").instantiate()
	root.add_child(theme_demo)
	await frames(10)
	await save("theme_demo")

	var settings := GameSettings.new()
	var screen := SettingsScreen.open_overlay(root, settings)
	await frames(10)
	await save("settings_screen")
	screen.closed.emit()
	theme_demo.queue_free()
	await frames(4)

	var sprite_demo: Control = load("res://ui/common/demo/sprite_demo.tscn").instantiate()
	root.add_child(sprite_demo)
	await frames(6)
	sprite_demo.freeze_on(0.5)
	await frames(4)
	await save("sprite_demo")
	sprite_demo.queue_free()
	await frames(4)

	var feel_demo: Control = load("res://ui/common/demo/feel_demo.tscn").instantiate()
	root.add_child(feel_demo)
	await frames(20)
	var began := Time.get_ticks_msec()
	var index := 0
	for ms: int in FEEL_FRAME_TIMES_MS:
		while Time.get_ticks_msec() - began < ms:
			await process_frame
		if ms == 0:
			await save("feel_frame_%02d_%04d" % [index, ms], FEEL_CROP)
			began = Time.get_ticks_msec()
			feel_demo._land_hit(30, true)
		else:
			await save("feel_frame_%02d_%04d" % [index, ms], FEEL_CROP)
		index += 1
	quit()
