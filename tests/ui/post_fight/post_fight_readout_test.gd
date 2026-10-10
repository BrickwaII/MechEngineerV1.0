extends GdUnitTestSuite
## The post-fight readout and its demo scene, headless.

const DEMO := "res://ui/post_fight/post_fight_demo.tscn"
const READOUT := "res://ui/post_fight/post_fight_readout.tscn"
const Readout := preload("res://ui/post_fight/post_fight_readout.gd")


func _texts(node: Node) -> PackedStringArray:
	var out := PackedStringArray()
	if node is Label:
		out.append(node.text)
	for child in node.get_children():
		out.append_array(_texts(child))
	return out


func test_demo_shows_one_panel_per_bot() -> void:
	var runner := scene_runner(DEMO)
	await runner.simulate_frames(2)
	var demo := runner.scene()
	assert_str(demo.report.error).is_empty()
	assert_int(demo.report.bots.size()).is_equal(3)
	for b: BotFightReport in demo.report.bots:
		assert_object(demo.readout.bot_panel(b.bot_id)).is_not_null()


func test_demo_panel_shows_counters_level_ups_and_shifts() -> void:
	var runner := scene_runner(DEMO)
	await runner.simulate_frames(2)
	var demo := runner.scene()
	var r: BotFightReport = demo.report.bots[0]
	demo.readout.skip()
	var texts := "\n".join(_texts(demo.readout.bot_panel(r.bot_id)))
	assert_str(texts).contains(r.display_name)
	assert_str(texts).contains("Hit an enemy")
	assert_str(texts).contains("LEVEL UP")
	assert_str(texts).contains("%+.2f" % r.shift(Personality.Scale.AGGRESSIVE_DEFENSIVE))
	# Generation 1: the other two scales are locked.
	assert_str(texts).contains("locked")


func test_demo_is_the_same_every_run() -> void:
	var a := (load("res://ui/post_fight/post_fight_demo.gd").new() as Control)
	var b := (load("res://ui/post_fight/post_fight_demo.gd").new() as Control)
	var ra: PostFightReport = a.build_canned_report()
	var rb: PostFightReport = b.build_canned_report()
	assert_int(ra.action_count).is_equal(rb.action_count)
	for i in ra.bots.size():
		assert_array(ra.bots[i].personality_after).is_equal(rb.bots[i].personality_after)
	a.free()
	b.free()


func test_an_error_report_says_so() -> void:
	var runner := scene_runner(READOUT)
	await runner.simulate_frames(1)
	var report := PostFightReport.new()
	report.error = "the fight is not over"
	runner.scene().show_report(report)
	assert_str("\n".join(_texts(runner.scene()))).contains("the fight is not over")


func _change(skill_name: String, uses: int, before: int, after: int, banked: int) -> SkillChange:
	var c := SkillChange.new()
	c.combat_skill_id = "patch_up"
	c.skill_name = skill_name
	c.uses = uses
	c.level_before = before
	c.level_after = after
	c.banked_after = banked
	c.uses_per_level = 5
	c.max_level = 10
	return c


func test_a_skill_row_shows_uses_and_progress_to_the_next_level() -> void:
	var c := _change("Patch Up", 3, 1, 1, 3)
	assert_str(Readout.skill_row_left(c)).is_equal("Patch Up ×3")
	assert_str(Readout.skill_row_right(c)).is_equal("Lv 1 · 3/5 to Lv 2")


func test_a_level_up_row_shows_the_new_level_and_progress() -> void:
	assert_str(Readout.skill_row_right(_change("Brace", 6, 1, 2, 1))).is_equal("LEVEL UP  1 > 2 · 1/5 to Lv 3")
	assert_str(Readout.skill_row_right(_change("Brace", 6, 9, 10, 1))).is_equal("LEVEL UP  9 > 10 · max")


func test_the_basic_attack_is_not_a_skill_to_train() -> void:
	var c := SkillChange.new()
	c.combat_skill_id = "strike"
	c.uses = 4
	assert_str(Readout.skill_row_left(c)).is_equal("Strike ×4")
	assert_str(Readout.skill_row_right(c)).is_equal("basic attack")


func test_the_readout_counts_up_then_shows_the_final_numbers() -> void:
	var runner := scene_runner(DEMO)
	await runner.simulate_frames(1)
	var demo := runner.scene()
	var readout: Control = demo.readout
	assert_bool(readout.is_tallying()).is_true()
	var r: BotFightReport = demo.report.bots[0]
	var count: int = r.label_counts[ActionTag.HIT_ENEMY]
	var row: Control = readout.bot_panel(r.bot_id).find_child("Count_%s" % ActionTag.HIT_ENEMY, true, false)
	# Rows start hidden at zero.
	assert_str(row.get_child(1).text).is_equal("0")
	var finished := [false]
	readout.tally_finished.connect(func() -> void: finished[0] = true)
	var guard := 0
	while readout.is_tallying() and guard < 600:
		await runner.simulate_frames(1, 16)
		guard += 1
	assert_bool(finished[0]).is_true()
	assert_str(row.get_child(1).text).is_equal(str(count))
	assert_float(row.modulate.a).is_equal(1.0)


func test_a_click_skips_to_the_end() -> void:
	var runner := scene_runner(DEMO)
	await runner.simulate_frames(1)
	var readout: Control = runner.scene().readout
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	readout._gui_input(click)
	assert_bool(readout.is_tallying()).is_false()
	var texts := "\n".join(_texts(readout))
	assert_str(texts).contains("LEVEL UP")
