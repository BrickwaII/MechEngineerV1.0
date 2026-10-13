extends SceneTree
## Renders the ways out of a run for pull requests. Needs a display:
##     xvfb-run -a -s "-screen 0 1600x1000x24" godot --path . --rendering-driver opengl3 \
##         --resolution 1280x820 -s res://ui/run/demo/capture_leave.gd -- <out_dir>
## Shots: the map with its Home button, the Esc menu over the map, the
## battle with its Home button, the leave-the-battle confirm, the readout
## with its Home button.

const ROOT := "user://capture_leave_runs"

var out_dir := "user://capture_out"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	var flow: RunFlow = load("res://ui/run/run_flow.tscn").instantiate()
	flow.run_seed = 13
	flow.runs_root = ROOT
	flow.variants_path = "user://capture_leave_variants.json"
	flow.exit_requested.connect(func() -> void: print("exit requested"))
	root.add_child(flow)
	await _settle(10)
	var screen := flow.draft_screen
	for i in screen.picker.squad_size():
		screen.cards[screen.picker.bots()[i].id].pressed.emit()
	screen.start_button.pressed.emit()
	await _settle(60)
	var ow: Control = flow.overworld
	await _save("leave_1_map_home_button")
	flow.open_pause_menu()
	await _settle(10)
	await _save("leave_2_map_esc_menu")
	flow.close_pause_menu()
	var target := _weakest(ow.campaign)
	ow._on_attack(target)
	await _settle(60)
	await _save("leave_3_battle_home_button")
	flow.go_home()
	await _settle(10)
	await _save("leave_4_battle_confirm")
	flow.pause_menu.stay_button.pressed.emit()
	flow.close_pause_menu()
	GameSettings.shared().animation_speed = "skip"
	var battle := flow.battle_screen
	var frames := 0
	while is_instance_valid(battle) and not battle.fight.is_over() and frames < 20000:
		frames += 1
		if frames % 600 == 0:
			print("fight at action %d, player turn %s, paused %s" % [battle.fight.action_count, battle.handler.is_player_turn(), paused])
		if battle.handler.is_player_turn():
			_take_turn(battle)
		await _settle(2)
	print("fight over")
	await _wait_until(func() -> bool: return flow.stage == RunFlow.Stage.POST_FIGHT)
	GameSettings.shared().animation_speed = "1x"
	flow.readout.skip()
	await _settle(30)
	await _save("leave_5_readout_home_button")
	flow.queue_free()
	await _settle(2)
	_remove_tree(ROOT)
	quit()


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


func _weakest(c: Campaign) -> String:
	var best: MapRegion = null
	for region in c.map.regions:
		if c.standing(region.id) == Campaign.Standing.IN_RANGE and (best == null or region.defense < best.defense):
			best = region
	return best.id if best != null else ""


func _wait_until(done: Callable) -> void:
	var guard := 0
	while not done.call() and guard < 3000:
		guard += 1
		await process_frame


func _settle(frames: int) -> void:
	for i in frames:
		await process_frame


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for name in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(name))
	for name in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(name))
	DirAccess.remove_absolute(path)
