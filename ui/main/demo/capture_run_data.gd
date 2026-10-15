extends CaptureScript
## Renders the run data screens for pull requests and writes a sample
## journal. Needs a display:
##     xvfb-run -a -s "-screen 0 1600x1000x24" godot --path . --rendering-driver opengl3 \
##         --resolution 1280x820 -s res://ui/main/demo/capture_run_data.gd -- <out_dir>
## Plays two real runs into a scratch runs folder (one on the battle screen,
## one with auto-fights through an act zoom), then shots: the map with OPEN
## RUN FOLDER, the F8 form, the main menu (with the old-save offer) and the
## load list. Copies the battle-screen run's journal to <out_dir>.

const ROOT := "user://capture_runs"
const LEGACY := "user://capture_runs_legacy.res"


func _init() -> void:
	start("user://capture_out")


func _run() -> void:
	remove_tree(ROOT)
	await _auto_run()
	await _battle_run()
	await _menu()
	quit()


func _flow(seed_value: int, auto: bool) -> RunFlow:
	var flow: RunFlow = load("res://ui/run/run_flow.tscn").instantiate()
	flow.run_seed = seed_value
	flow.auto_fights = auto
	flow.runs_root = ROOT
	flow.variants_path = "user://capture_runs_variants.json"
	flow.folder_opener = func(path: String) -> void: print("would open ", path)
	root.add_child(flow)
	await frames(10)
	var screen := flow.draft_screen
	for i in screen.picker.squad_size():
		screen.cards[screen.picker.bots()[i].id].pressed.emit()
	screen.start_button.pressed.emit()
	await frames(20)
	return flow


## Act 1 to its payload with auto-fights, the zoom, a few days of act 2.
func _auto_run() -> void:
	var flow := await _flow(5, true)
	var ow: Control = flow.overworld
	var guard := 0
	while not ow.campaign.is_payload_due() and not ow.campaign.is_lost() and guard < 600:
		guard += 1
		if not ow.campaign.pending_defense().is_empty():
			ow._on_defend()
			await frames(3)
			_close_modal(ow)
		elif guard % 9 == 0 and ow.campaign.state.grid > 40.0:
			var target := weakest(ow.campaign)
			if not target.is_empty():
				ow._on_attack(target)
				await frames(3)
				_close_modal(ow)
		else:
			ow._on_wait()
		await process_frame
	if ow.campaign.is_payload_due():
		ow.zoom_out()
		await wait_until(func() -> bool: return not ow.zooming)
		for i in 6:
			ow._on_wait()
	flow.queue_free()
	await frames(2)


## Two attacks fought on the battle screen, some waits, a reinforce, a save,
## then the map shot and the F8 form.
func _battle_run() -> void:
	# Battles play with animations skipped; the shots come after.
	GameSettings.shared().animation_speed = "skip"
	var flow := await _flow(13, false)
	var ow: Control = flow.overworld
	ow._on_wait()
	for fight in 2:
		var target := weakest(ow.campaign)
		flow._on_region_selected(target)
		ow._on_attack(target)
		await frames(2)
		await _play(flow.battle_screen)
		await wait_until(func() -> bool: return flow.stage == RunFlow.Stage.POST_FIGHT)
		await frames(10)
		flow.continue_to_map()
		await frames(10)
		_close_modal(ow)
		ow._on_wait()
		ow._on_reinforce(ow.campaign.state.owned[0])
	flow.save_run()
	GameSettings.shared().animation_speed = "1x"
	await frames(40)
	await save("map_open_run_folder")
	flow.open_feedback()
	await frames(4)
	flow.feedback_form.note_edit.text = "Act 1 feels slow after the second capture: I waited through days 9 to 20 with nothing to do."
	flow.feedback_form.category_picker.select(1)
	flow.feedback_form.mood_buttons[1].button_pressed = true
	await frames(10)
	await save("f8_form")
	flow.feedback_form.save_button.pressed.emit()
	await frames(4)
	DirAccess.copy_absolute(RunFolder.journal_path(flow.run_dir), out_dir.path_join("sample_journal.jsonl"))
	print("report: ", flow.last_report_dir)
	flow.queue_free()
	await frames(2)


## Each bot turn: the last affordable damage skill (a bot's own before Strike)
## on the first living enemy.
func _play(screen: BattleScreen) -> void:
	var fight := screen.fight
	var frame_count := 0
	while not fight.is_over():
		frame_count += 1
		if frame_count % 600 == 0:
			print("fight at action %d, actor %s, player turn %s" % [fight.action_count, screen.handler.actor(), screen.handler.is_player_turn()])
		if not screen.handler.is_player_turn():
			await process_frame
			continue
		var actor := screen.handler.actor()
		var acted := false
		var skills := actor.skills()
		skills.reverse()
		for skill in skills:
			if not skill.is_damage() or not screen.handler.skill_problem(skill.id).is_empty():
				continue
			screen.send(FightCommand.select_skill(skill.id))
			if screen.handler.is_choosing_target():
				for enemy in fight.opponents_of(actor):
					if screen.handler.target_problem(enemy.id).is_empty():
						screen.send(FightCommand.select_target(enemy.id))
						break
			acted = true
			break
		if not acted:
			screen.send(FightCommand.wait())
		await frames(2)


func _menu() -> void:
	var squad := BotFactory.new(BotTuning.load_default()).build_squad(99)
	var map := RegionMap.load_file("res://data/regions/lake_washington_12.json")
	var tuning := MapTuning.load_file("res://data/tuning/act1.json")
	var state := Campaign.new_run_state(map, tuning, map.start_options()[0], CampaignVariants.defaults())
	state.time_points = 37
	RunSave.make(99, squad, SkillUseLedger.new(), state).save_file(LEGACY)
	var menu: MainMenu = load("res://ui/main/main.tscn").instantiate()
	menu.runs_root = ROOT
	menu.legacy_save = LEGACY
	root.add_child(menu)
	await frames(20)
	await save("main_menu")
	menu.import_legacy()
	menu.show_load_list()
	await frames(20)
	await save("load_list")
	menu.queue_free()


func _close_modal(ow: Control) -> void:
	if ow._modal.visible and ow._modal_buttons.get_child_count() > 0:
		(ow._modal_buttons.get_child(0) as Button).pressed.emit()
