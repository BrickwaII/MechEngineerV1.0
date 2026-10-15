extends CaptureScript
## Shots of the menu and demo scenarios at one window size, for screen-fit
## pull requests. It grabs the whole X screen (ImageMagick's `import`) when it
## can, so anything outside the view (black bars) shows; else the view. Make
## the X screen exactly the window size:
##     xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
##         --resolution 1920x1080 -s res://ui/demo/capture_sizes.gd -- <out_dir> [id ...]
## Ids are demo scenario ids, plus "menu" for the main menu and "settings" for
## the settings screen. With none it shoots the menu, act 1's map and fight.

const DEFAULT_IDS: Array[String] = ["menu", "act1_map_early", "act1_fight"]


func _init() -> void:
	start("user://capture_out", true, DEFAULT_IDS)


func _run() -> void:
	await frames(5)
	var tag := "%dx%d" % [root.size.x, root.size.y]
	for id in only:
		var node: Node
		if id == "menu" or id == "settings":
			var menu: Node = load("res://ui/main/main.tscn").instantiate()
			menu.set("show_whats_new", false)
			node = menu
			root.add_child(node)
			if id == "settings":
				SettingsScreen.open_overlay(root)
		else:
			var scenario: DemoScenario = null
			for s in DemoScenario.load_all():
				if s.id == id:
					scenario = s
			if scenario == null:
				push_warning("no scenario %s" % id)
				continue
			var flow := DemoRunFlow.new()
			flow.scenario = scenario
			flow.folder_opener = func(_path: String) -> void: pass
			node = flow
			root.add_child(node)
		await frames(80)
		await save("%s_%s" % [id, tag])
		var overlay := root.get_node_or_null("SettingsOverlay")
		if overlay != null:
			overlay.free()
		node.queue_free()
		await frames(3)
	quit()


func save(file: String, _crop := Rect2i()) -> void:
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path(out_dir.path_join(file + ".png"))
	if OS.execute("import", ["-window", "root", path]) != 0:
		root.get_texture().get_image().save_png(path)
	print("saved ", file)
