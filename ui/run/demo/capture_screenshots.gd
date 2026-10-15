extends CaptureScript
## Renders the M7 P3 screens to PNGs for pull requests. Needs a display:
##     xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1280x820 \
##         -s res://ui/run/demo/capture_screenshots.gd -- <out_dir> [shots]
## shots is a comma list of: acts, capture, zoom, draft, readout, transition
## (all by default). Frame strips are one PNG of frames side by side.

const OVERWORLD := "res://ui/overworld/overworld.tscn"

var shots := PackedStringArray(["acts", "capture", "zoom", "draft", "readout", "transition"])


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 1:
		shots = args[1].split(",")
	start("res://ui/run/screenshots")


func _run() -> void:
	for shot in shots:
		await call("_shot_" + shot)
		await frames(4)
	quit()


# --- Acts with hover and selection -------------------------------------------------

func _shot_acts() -> void:
	var screen: Control = load(OVERWORLD).instantiate()
	screen.start_picker = func(options: Array) -> String: return options[0].id
	root.add_child(screen)
	await frames(6)
	await _hover_and_select(screen, "act1_hover_select", "north_seattle", "bothell")
	screen.campaign.state.time_points = screen.campaign.tuning.total_points - 1
	screen._on_wait()
	screen.zoom_out()
	await wait_until(func() -> bool: return not screen.zooming, -1)
	await frames(30)
	await _hover_and_select(screen, "act2_hover_select", "oregon", "idaho")
	screen.campaign.state.time_points = screen.campaign.tuning.total_points - 1
	screen._on_wait()
	screen.zoom_out()
	await wait_until(func() -> bool: return not screen.zooming, -1)
	await frames(30)
	await _hover_and_select(screen, "act3_hover_select", "canada", "mexico")
	screen.queue_free()


func _hover_and_select(screen: Control, name: String, select_id: String, hover_id: String) -> void:
	var view: Control = screen.map_view
	if not screen.campaign.map.has_region(select_id):
		select_id = _first_hostile(screen)
	if not screen.campaign.map.has_region(hover_id):
		hover_id = _first_hostile(screen, select_id)
	view.select(select_id)
	view._hover_at(view.label_position(hover_id))
	await frames(30)
	await save(name)


func _first_hostile(screen: Control, other := "") -> String:
	for region in screen.campaign.map.regions:
		if screen.campaign.standing(region.id) == Campaign.Standing.IN_RANGE and region.id != other:
			return region.id
	return ""


# --- Capture frame strip -----------------------------------------------------------

func _shot_capture() -> void:
	var screen: Control = load(OVERWORLD).instantiate()
	screen.start_picker = func(options: Array) -> String: return options[0].id
	root.add_child(screen)
	await frames(6)
	var target := "north_seattle"
	screen.map_view.select(target)
	await frames(4)
	screen._on_attack(target)
	await wait_until(func() -> bool: return screen._modal.visible, -1)
	await frames(4)
	var view: Control = screen.map_view
	var at: Vector2 = view.label_position(target) + view.global_position
	var crop := Rect2i(Rect2(at - Vector2(170, 150), Vector2(340, 300)))
	var shots: Array[Image] = []
	shots.append(await grab(crop))
	var close: Button = screen._modal_buttons.get_child(0)
	close.pressed.emit()
	var began := Time.get_ticks_msec()
	for ms: int in [40, 140, 260, 400, 560, 760, 1000]:
		while Time.get_ticks_msec() - began < ms:
			await process_frame
		shots.append(await grab(crop))
	await save_strip("capture_frame_strip", shots)
	await frames(30)
	await save("capture_after")
	screen.queue_free()


# --- Act zoom frame strip ----------------------------------------------------------

func _shot_zoom() -> void:
	var screen: Control = load(OVERWORLD).instantiate()
	screen.start_picker = func(options: Array) -> String: return options[0].id
	root.add_child(screen)
	await frames(6)
	for act in 2:
		screen.campaign.state.time_points = screen.campaign.tuning.total_points - 1
		screen._on_wait()
		await frames(2)
		var shots: Array[Image] = []
		screen.zoom_out()
		var began := Time.get_ticks_msec()
		for ms: int in [0, 250, 500, 750, 1000, 1300, 1700, 2100]:
			while Time.get_ticks_msec() - began < ms:
				await process_frame
			var frame := await grab()
			frame.resize(frame.get_width() / 2, frame.get_height() / 2, Image.INTERPOLATE_BILINEAR)
			shots.append(frame)
		await wait_until(func() -> bool: return not screen.zooming, -1)
		await save_strip("act_zoom_%d_to_%d_frame_strip" % [act + 1, act + 2], shots)
		await frames(20)
	screen.queue_free()


# --- Draft -------------------------------------------------------------------------

func _shot_draft() -> void:
	var draft: DraftScreen = load("res://ui/draft/draft_screen.tscn").instantiate()
	draft.draft_seed = 5
	root.add_child(draft)
	await frames(2)
	var shots: Array[Image] = []
	var began := Time.get_ticks_msec()
	for ms: int in [0, 120, 240, 360, 480, 700]:
		while Time.get_ticks_msec() - began < ms:
			await process_frame
		var frame := await grab()
		frame.resize(frame.get_width() / 2, frame.get_height() / 2, Image.INTERPOLATE_BILINEAR)
		shots.append(frame)
	await save_strip("draft_flip_in_frame_strip", shots, 3)
	var bots := draft.picker.bots()
	draft.cards[bots[1].id].pressed.emit()
	draft.cards[bots[3].id].pressed.emit()
	await frames(40)
	draft.cards[bots[2].id].mouse_entered.emit()
	await frames(20)
	await save("draft_with_sprites")
	draft.queue_free()


# --- Post-fight count-up -----------------------------------------------------------

func _shot_readout() -> void:
	var demo: Control = load("res://ui/post_fight/post_fight_demo.tscn").instantiate()
	root.add_child(demo)
	var shots: Array[Image] = []
	var began := Time.get_ticks_msec()
	var total: float = demo.readout.tally.total_seconds() * 1000.0
	for i in 12:
		var ms := int(total * i / 11.0)
		while Time.get_ticks_msec() - began < ms:
			await process_frame
		var frame := await grab()
		frame.resize(frame.get_width() / 2, frame.get_height() / 2, Image.INTERPOLATE_BILINEAR)
		shots.append(frame)
	await save_strip("readout_count_up_frame_strip", shots)
	await frames(30)
	await save("readout_final")
	demo.queue_free()


# --- Transition --------------------------------------------------------------------

func _shot_transition() -> void:
	var flow: RunFlow = load("res://ui/run/run_flow.tscn").instantiate()
	flow.run_seed = 5
	flow.auto_fights = true
	root.add_child(flow)
	await frames(30)
	var bots := flow.draft_screen.picker.bots()
	for i in flow.draft_screen.picker.squad_size():
		flow.draft_screen.cards[bots[i].id].pressed.emit()
	await frames(30)
	var shots: Array[Image] = []
	flow.draft_screen.start_button.pressed.emit()
	var began := Time.get_ticks_msec()
	for ms: int in [0, 60, 120, 180, 240, 320]:
		while Time.get_ticks_msec() - began < ms:
			await process_frame
		var frame := await grab()
		frame.resize(frame.get_width() / 2, frame.get_height() / 2, Image.INTERPOLATE_BILINEAR)
		shots.append(frame)
	await save_strip("transition_draft_to_map_frame_strip", shots, 3)
	flow.queue_free()


# --- Helpers -----------------------------------------------------------------------
