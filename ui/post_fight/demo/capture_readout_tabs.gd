extends CaptureScript
## Shots of the post-fight readout's tabs for pull requests: Summary, Growth
## and Details after the count-up, and a bot's detail card. On a readout
## without tabs it saves the one page. Needs a display:
##     xvfb-run -a -s "-screen 0 1600x1000x24" godot --path . --rendering-driver opengl3 \
##         --resolution 1280x820 -s res://ui/post_fight/demo/capture_readout_tabs.gd -- <out_dir>


func _init() -> void:
	start("user://capture_out")


func _run() -> void:
	var demo: Control = load("res://ui/post_fight/post_fight_demo.tscn").instantiate()
	root.add_child(demo)
	await frames(6)
	demo.readout.skip()
	await frames(6)
	var readout: Control = demo.readout
	if not "tabs" in readout:
		await save("readout")
		quit()
		return
	for id in [&"summary", &"growth", &"details"]:
		readout.tabs.select(id)
		await frames(4)
		await save("readout_%s" % id)
	readout.tabs.select(&"summary")
	await frames(2)
	var card: InfoCard = readout.find_children("Summary_*", "", true, false)[0]
	card.open_detail()
	await frames(6)
	await save("readout_summary_detail")
	quit()
