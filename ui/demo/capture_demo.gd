extends CaptureScript
## Renders the demo screens for pull requests. Needs a display:
##     xvfb-run -a -s "-screen 0 1600x1000x24" godot --path . --rendering-driver opengl3 \
##         --resolution 1280x820 -s res://ui/demo/capture_demo.gd -- <out_dir> [scenario id ...]
## Shots: the main menu with DEMO, the picker, every scenario in data/demo/
## (or only the ids given) as it opens, the Esc menu in a demo, and a demo
## fight's end panel. Nothing is saved; F8 is not pressed.


func _init() -> void:
	start("user://capture_out", true)


func _run() -> void:
	if only.is_empty():
		await _menu_and_picker()
	var shown_end := false
	for s in DemoScenario.load_all():
		if not only.is_empty() and not s.id in only:
			continue
		var flow := DemoRunFlow.new()
		flow.scenario = s
		flow.folder_opener = func(path: String) -> void: print("would open ", path)
		root.add_child(flow)
		await frames(30 if s.kind == DemoScenario.KIND_FIGHT else 80)
		await save("demo_%s" % s.id)
		if flow.overworld != null and flow.overworld.map_view.has_method("drag_by") and s.id == "act3_globe":
			# The globe turns under a drag: the same as dragging it with the mouse.
			flow.overworld.map_view.drag_by(Vector2(-260, 40))
			await frames(6)
			await save("demo_%s_dragged" % s.id)
		if s.kind == DemoScenario.KIND_FIGHT and not shown_end and only.is_empty():
			shown_end = true
			flow.open_pause_menu()
			await frames(6)
			await save("demo_esc_menu")
			flow.close_pause_menu()
			await _play_to_end(flow)
			await save("demo_end_panel")
		flow.queue_free()
		await frames(3)
	quit()


func _menu_and_picker() -> void:
	var menu: MainMenu = load("res://ui/main/main.tscn").instantiate()
	menu.runs_root = "user://capture_demo_runs"
	root.add_child(menu)
	await frames(20)
	await save("demo_main_menu")
	menu.show_demos()
	await frames(20)
	await save("demo_picker")
	menu.queue_free()
	await frames(3)


func _play_to_end(flow: DemoRunFlow) -> void:
	GameSettings.shared().animation_speed = "skip"
	var battle := flow.battle_screen
	var frame_count := 0
	while is_instance_valid(battle) and not battle.fight.is_over() and frame_count < 20000:
		frame_count += 1
		if battle.handler.is_player_turn():
			take_turn(battle)
		await process_frame
		await process_frame
	var guard := 0
	while flow.stage != RunFlow.Stage.POST_FIGHT and guard < 3000:
		guard += 1
		await process_frame
	GameSettings.shared().animation_speed = "1x"
	if flow.readout != null:
		flow.readout.skip()
		flow.continue_to_map()
	await frames(20)
