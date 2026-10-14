extends SceneTree
## Shots of the post-fight readout's tabs for pull requests: Summary, Growth
## and Details after the count-up, and a bot's detail card. On a readout
## without tabs it saves the one page. Needs a display:
##     xvfb-run -a -s "-screen 0 1600x1000x24" godot --path . --rendering-driver opengl3 \
##         --resolution 1280x820 -s res://ui/post_fight/demo/capture_readout_tabs.gd -- <out_dir>

var out_dir := "user://capture_out"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	var demo: Control = load("res://ui/post_fight/post_fight_demo.tscn").instantiate()
	root.add_child(demo)
	await _frames(6)
	demo.readout.skip()
	await _frames(6)
	var readout: Control = demo.readout
	if not "tabs" in readout:
		await _save("readout")
		quit()
		return
	for id in [&"summary", &"growth", &"details"]:
		readout.tabs.select(id)
		await _frames(4)
		await _save("readout_%s" % id)
	readout.tabs.select(&"summary")
	await _frames(2)
	var card: InfoCard = readout.find_children("Summary_*", "", true, false)[0]
	card.open_detail()
	await _frames(6)
	await _save("readout_summary_detail")
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(file: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(file + ".png"))
	print("saved ", file)
