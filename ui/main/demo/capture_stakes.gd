extends SceneTree
## Renders the stakes and economy screens (R2-A) for pull requests. Needs a
## display:
##     xvfb-run -a -s "-screen 0 1600x1000x24" godot --path . --rendering-driver opengl3 \
##         --resolution 1280x820 -s res://ui/main/demo/capture_stakes.gd -- <out_dir>
## One auto-fight run into a scratch runs folder: the map with the losses
## label, REPAIR and the resource tooltip text; the pre-fight step; a forced
## defense with RETREAT; fast-forward once the map is taken (set by hand) and
## its summary; a second run that attacks the toughest regions until its
## third loss ends it, and its run-over screen; the
## load list with the finished run's VIEW and its read-only run-over screen.

const ROOT := "user://capture_stakes_runs"

var out_dir := "user://capture_out"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	_remove_tree(ROOT)
	await _stakes_run()
	await _losing_run()
	await _menu()
	quit()


func _flow(seed_value: int) -> RunFlow:
	var flow: RunFlow = load("res://ui/run/run_flow.tscn").instantiate()
	flow.run_seed = seed_value
	flow.auto_fights = true
	flow.runs_root = ROOT
	flow.variants_path = "user://capture_stakes_variants.json"
	flow.folder_opener = func(path: String) -> void: print("would open ", path)
	root.add_child(flow)
	await _settle(10)
	var screen := flow.draft_screen
	for i in screen.picker.squad_size():
		screen.cards[screen.picker.bots()[i].id].pressed.emit()
	screen.start_button.pressed.emit()
	await _settle(20)
	return flow


func _stakes_run() -> void:
	var flow := await _flow(5)
	var ow: Control = flow.overworld
	var c: Campaign = ow.campaign
	for i in 6:
		ow._on_wait()
	c.state.losses = 1
	c.state.material = 14.0
	c.state.grid = 72.0
	c.changed.emit()
	var target := _weakest(c)
	ow.map_view.select(target)
	await _settle(30)
	await _save("stakes_map")
	print("energy tooltip:\n", ow.resource_tooltip("energy"))
	print("material tooltip:\n", ow.resource_tooltip("material"))
	ow.show_pre_fight(target)
	await _settle(20)
	await _save("stakes_pre_fight")
	ow._hide_modal()

	var held: String = c.state.owned[0]
	c.state.pressure[held] = c.tuning.forces_defense_at
	c.changed.emit()
	ow._check_forced()
	await _settle(20)
	await _save("stakes_forced_defense_retreat")
	ow._hide_modal()
	c.state.pressure[held] = 10.0

	# The act's map taken (by hand, for the shot): FAST-FORWARD shows.
	c.state.owned = c.map.ids()
	for id in c.state.owned:
		c.state.pressure[id] = 20.0
	c.state.energy = 60.0
	c.changed.emit()
	ow.map_view.select("")
	await _settle(30)
	await _save("stakes_fast_forward_button")
	ow._on_fast_forward()
	await _settle(30)
	await _save("stakes_fast_forward_summary")
	ow._hide_modal()

	flow.queue_free()
	await _settle(2)


## A fight service that loses every fight, a frame after it starts.
class LosingService:
	extends FightService

	func start_fight(_request: FightRequest) -> void:
		var result := FightResult.new(FightResult.Outcome.DEFEAT)
		Engine.get_main_loop().process_frame.connect(func() -> void: finished.emit(result), CONNECT_ONE_SHOT)


## A run lost through the real rules: every fight is a scripted loss (the
## auto-fighting squad wins too often to show this), attacking the toughest
## region in range until the loss limit ends the run.
func _losing_run() -> void:
	var flow := await _flow(7)
	var ow: Control = flow.overworld
	var c: Campaign = ow.campaign
	c.fight_service = LosingService.new()
	var guard := 0
	while c.end_reason().is_empty() and guard < 40:
		guard += 1
		if not c.pending_defense().is_empty():
			ow._on_defend()
		else:
			var target := _toughest(c)
			if target.is_empty():
				break
			ow._on_attack(target)
		await _settle(4)
		if ow._modal.visible and not c.is_over():
			(ow._modal_buttons.get_child(0) as Button).pressed.emit()
			await _settle(2)
	print("losing run: %s after %d fights, %d lost" % [c.end_reason(), guard, c.state.losses])
	# The last defeat's message first, then the run-over message.
	(ow._modal_buttons.get_child(0) as Button).pressed.emit()
	await _settle(20)
	await _save("stakes_loss_limit_message")
	(ow._modal_buttons.get_child(0) as Button).pressed.emit()
	await _settle(30)
	await _save("run_over_screen")
	flow.queue_free()
	await _settle(2)


func _menu() -> void:
	var menu: MainMenu = load("res://ui/main/main.tscn").instantiate()
	menu.runs_root = ROOT
	menu.legacy_save = "user://capture_stakes_no_legacy.res"
	root.add_child(menu)
	await _settle(10)
	menu.show_load_list()
	await _settle(20)
	await _save("load_list_view_finished")
	for dir: String in menu.load_buttons:
		if menu.load_buttons[dir].text == "VIEW":
			menu.view_finished_run(dir)
			break
	await _settle(20)
	await _save("run_over_read_only")
	menu.queue_free()


func _toughest(c: Campaign) -> String:
	var best: MapRegion = null
	for region in c.map.regions:
		if c.standing(region.id) == Campaign.Standing.IN_RANGE and (best == null or region.defense > best.defense):
			best = region
	return best.id if best != null else ""


func _weakest(c: Campaign) -> String:
	var best: MapRegion = null
	for region in c.map.regions:
		if c.standing(region.id) == Campaign.Standing.IN_RANGE and (best == null or region.defense < best.defense):
			best = region
	return best.id if best != null else ""


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
