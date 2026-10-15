extends CaptureScript
## Renders the ways out of a run for pull requests. Needs a display:
##     xvfb-run -a -s "-screen 0 1600x1000x24" godot --path . --rendering-driver opengl3 \
##         --resolution 1280x820 -s res://ui/run/demo/capture_leave.gd -- <out_dir>
## Shots: the map with its Home button, the Esc menu over the map, the
## battle with its Home button, the leave-the-battle confirm, the readout
## with its Home button.

const ROOT := "user://capture_leave_runs"


func _init() -> void:
	start("user://capture_out")


func _run() -> void:
	var flow: RunFlow = load("res://ui/run/run_flow.tscn").instantiate()
	flow.run_seed = 13
	flow.runs_root = ROOT
	flow.variants_path = "user://capture_leave_variants.json"
	flow.exit_requested.connect(func() -> void: print("exit requested"))
	root.add_child(flow)
	await frames(10)
	var screen := flow.draft_screen
	for i in screen.picker.squad_size():
		screen.cards[screen.picker.bots()[i].id].pressed.emit()
	screen.start_button.pressed.emit()
	await frames(60)
	var ow: Control = flow.overworld
	await save("leave_1_map_home_button")
	flow.open_pause_menu()
	await frames(10)
	await save("leave_2_map_esc_menu")
	flow.close_pause_menu()
	var target := weakest(ow.campaign)
	ow._on_attack(target)
	await frames(60)
	await save("leave_3_battle_home_button")
	flow.go_home()
	await frames(10)
	await save("leave_4_battle_confirm")
	flow.pause_menu.stay_button.pressed.emit()
	flow.close_pause_menu()
	GameSettings.shared().animation_speed = "skip"
	var battle := flow.battle_screen
	var frame_count := 0
	while is_instance_valid(battle) and not battle.fight.is_over() and frame_count < 20000:
		frame_count += 1
		if frame_count % 600 == 0:
			print("fight at action %d, player turn %s, paused %s" % [battle.fight.action_count, battle.handler.is_player_turn(), paused])
		if battle.handler.is_player_turn():
			take_turn(battle)
		await frames(2)
	print("fight over")
	await wait_until(func() -> bool: return flow.stage == RunFlow.Stage.POST_FIGHT)
	GameSettings.shared().animation_speed = "1x"
	flow.readout.skip()
	await frames(30)
	await save("leave_5_readout_home_button")
	flow.queue_free()
	await frames(2)
	remove_tree(ROOT)
	quit()
