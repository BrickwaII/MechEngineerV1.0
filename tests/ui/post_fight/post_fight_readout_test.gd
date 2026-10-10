extends GdUnitTestSuite
## The post-fight readout and its demo scene, headless.

const DEMO := "res://ui/post_fight/post_fight_demo.tscn"
const READOUT := "res://ui/post_fight/post_fight_readout.tscn"


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
