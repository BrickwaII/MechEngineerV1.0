extends CaptureScript
## Renders the growth readout to PNGs for pull requests. Needs a display:
##     xvfb-run -a -s "-screen 0 1600x1000x24" godot --path . --rendering-driver opengl3 \
##         --resolution 1280x820 -s res://ui/post_fight/demo/capture_growth.gd -- <out_dir>
## Shots: the rank-up and tier-up callouts (each a frame strip and a still),
## the personality hexagon growing (a frame strip), the readout at the end,
## the draft cards with their hexagons, and the bot builder's personality.


func _init() -> void:
	start("res://ui/post_fight/screenshots")


func _run() -> void:
	await _readout()
	await frames(4)
	await _draft()
	await frames(4)
	await _builder()
	quit()


func _readout() -> void:
	var demo: Control = load("res://ui/post_fight/post_fight_demo.tscn").instantiate()
	root.add_child(demo)
	await frames(2)
	var readout: Control = demo.readout
	var tally: TallySequence = readout.tally
	var rank_step := -1
	var tier_step := -1
	var grow_step := -1
	for i in tally.steps.size():
		var s := tally.steps[i]
		if s.kind == "level_up" and s.change.is_tier_shift() and tier_step < 0:
			tier_step = i
		elif s.kind == "level_up" and rank_step < 0:
			rank_step = i
		elif s.kind == "grow" and grow_step < 0:
			grow_step = i
	await _callout_strip(readout, rank_step, "growth_rank_up")
	await _callout_strip(readout, tier_step, "growth_tier_up")
	await _until_step(readout, tally.steps.size())
	await frames(30)
	await save("growth_readout_final")
	demo.queue_free()
	await frames(4)
	# The hexagon of the first bot that grew: a fresh demo, cropped to its chart.
	demo = load("res://ui/post_fight/post_fight_demo.tscn").instantiate()
	root.add_child(demo)
	await frames(2)
	readout = demo.readout
	# The last bot that grew: its shape has the most corners in the demo.
	grow_step = -1
	for i in readout.tally.steps.size():
		if readout.tally.steps[i].kind == "grow":
			grow_step = i
	await _until_step(readout, grow_step)
	var box: Control = readout.bot_panel(demo.report.bots[readout.tally.steps[grow_step].bot].bot_id).find_child("Hexagon", true, false)
	await frames(2)
	var crop := Rect2i(box.get_global_rect().grow(8))
	var shots: Array[Image] = []
	var duration: float = readout.tally.steps[grow_step].duration
	var began := Time.get_ticks_msec()
	for i in 8:
		var ms := int(duration * 1000.0 * i / 7.0)
		while Time.get_ticks_msec() - began < ms:
			await process_frame
		shots.append(await grab(crop))
	await save_strip("growth_hexagon_fill_frame_strip", shots, 4)
	demo.queue_free()


## Waits for `step` to start, grabs shots through it, saves a strip and the
## frame at its peak.
func _callout_strip(readout: Control, step: int, name: String) -> void:
	if step < 0:
		push_error("no %s step in the demo" % name)
		return
	await _until_step(readout, step)
	var duration: float = readout.tally.steps[step].duration
	var shots: Array[Image] = []
	var began := Time.get_ticks_msec()
	var peak: Image
	for i in 6:
		var ms := int(duration * 1000.0 * i / 6.0)
		while Time.get_ticks_msec() - began < ms:
			await process_frame
		var frame := await grab()
		if i == 3:
			peak = frame.duplicate()
		frame.resize(frame.get_width() / 2, frame.get_height() / 2, Image.INTERPOLATE_BILINEAR)
		shots.append(frame)
	await save_strip(name + "_frame_strip", shots, 3)
	peak.save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)


func _until_step(readout: Control, step: int) -> void:
	var guard := 0
	while readout.tally.current < step and guard < 5000:
		await process_frame
		guard += 1


func _draft() -> void:
	var draft: DraftScreen = load("res://ui/draft/draft_screen.tscn").instantiate()
	draft.draft_seed = 5
	root.add_child(draft)
	await frames(90)
	await save("growth_draft_hexagons")
	draft.queue_free()


func _builder() -> void:
	var builder: Control = load("res://ui/dev/bot_builder.tscn").instantiate()
	builder.bot_dir = "user://capture_growth_bots"
	builder.enemy_dir = "user://capture_growth_enemies"
	root.add_child(builder)
	await frames(4)
	var bot := BotLibrary.new_bot(BotTuning.load_default(), "demo", "Demo")
	bot.personality.aggressive = 1.4
	bot.personality.defensive = 0.6
	bot.personality.supportive = 0.9
	bot.personality.solitary = 0.2
	bot.personality.methodical = 0.5
	builder.show_bot(bot)
	await frames(10)
	await save("growth_bot_builder_personality")
	builder.queue_free()
