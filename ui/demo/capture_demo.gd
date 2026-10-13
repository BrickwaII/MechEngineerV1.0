extends SceneTree
## Renders the demo screens for pull requests. Needs a display:
##     xvfb-run -a -s "-screen 0 1600x1000x24" godot --path . --rendering-driver opengl3 \
##         --resolution 1280x820 -s res://ui/demo/capture_demo.gd -- <out_dir> [scenario id ...]
## Shots: the main menu with DEMO, the picker, every scenario in data/demo/
## (or only the ids given) as it opens, the Esc menu in a demo, and a demo
## fight's end panel. Nothing is saved; F8 is not pressed.

var out_dir := "user://capture_out"
var only: PackedStringArray = []


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
		only = args.slice(1)
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


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
		await _settle(false, 30 if s.kind == DemoScenario.KIND_FIGHT else 80)
		await _save("demo_%s" % s.id)
		if flow.overworld != null and flow.overworld.map_view.has_method("drag_by") and s.id == "act3_globe":
			# The globe turns under a drag: the same as dragging it with the mouse.
			flow.overworld.map_view.drag_by(Vector2(-260, 40))
			await _settle(false, 6)
			await _save("demo_%s_dragged" % s.id)
		if s.kind == DemoScenario.KIND_FIGHT and not shown_end and only.is_empty():
			shown_end = true
			flow.open_pause_menu()
			await _settle(false, 6)
			await _save("demo_esc_menu")
			flow.close_pause_menu()
			await _play_to_end(flow)
			await _save("demo_end_panel")
		flow.queue_free()
		await _settle(false, 3)
	quit()


func _menu_and_picker() -> void:
	var menu: MainMenu = load("res://ui/main/main.tscn").instantiate()
	menu.runs_root = "user://capture_demo_runs"
	root.add_child(menu)
	await _settle(false, 20)
	await _save("demo_main_menu")
	menu.show_demos()
	await _settle(false, 20)
	await _save("demo_picker")
	menu.queue_free()
	await _settle(false, 3)


func _play_to_end(flow: DemoRunFlow) -> void:
	GameSettings.shared().animation_speed = "skip"
	var battle := flow.battle_screen
	var frames := 0
	while is_instance_valid(battle) and not battle.fight.is_over() and frames < 20000:
		frames += 1
		if battle.handler.is_player_turn():
			_take_turn(battle)
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
	await _settle(false, 20)


func _take_turn(battle: BattleScreen) -> void:
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


func _settle(_fight: bool, frames: int) -> void:
	for i in frames:
		await process_frame


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)
