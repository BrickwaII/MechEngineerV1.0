extends SceneTree
## Checks that every play screen fits (ScreenFit) and saves a picture of each.
## In a real window it checks that window as the player would see it:
##     xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
##         --resolution 1920x1080 -s res://ui/demo/check_fit.gd -- <out_dir> [screen id ...]
## Headless (--headless) it lays the screens out at every view size the
## supported windows and interface sizes give, and saves no pictures.
## Prints each problem; the exit code is 1 when there are any.

var out_dir := ""
var ids: Array[String] = []


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
		for id in args.slice(1):
			ids.append(id)
	if ids.is_empty():
		ids = ScreenFit.screen_ids()
	if not out_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var headless := DisplayServer.get_name() == "headless"
	var views: Array[Vector2] = []
	if headless:
		views = ScreenFit.view_sizes()
	var shot := Callable() if headless or out_dir.is_empty() else _save
	var found: Dictionary = await ScreenFit.run(root, ids, views, shot)
	for id: String in found:
		for line: String in found[id]:
			print("%s: %s" % [id, line])
	print("%d of %d screens fit." % [ids.size() - found.size(), ids.size()])
	quit(1 if not found.is_empty() else 0)


func _save(id: String, view: Vector2) -> void:
	await RenderingServer.frame_post_draw
	var file := "%s_%dx%d.png" % [id, root.size.x, root.size.y]
	root.get_texture().get_image().save_png(out_dir.path_join(file))
