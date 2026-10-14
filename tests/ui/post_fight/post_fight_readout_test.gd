extends GdUnitTestSuite
## The post-fight readout and its demo scene, headless.
const Legacy := preload("res://tests/fight/legacy_switches.gd")

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


func test_demo_panel_shows_counters_rank_ups_and_growth() -> void:
	var runner := scene_runner(DEMO)
	await runner.simulate_frames(2)
	var demo := runner.scene()
	var r: BotFightReport = demo.report.bots[0]
	demo.readout.skip()
	var panel: Control = demo.readout.bot_panel(r.bot_id)
	var texts := "\n".join(_texts(panel))
	assert_str(texts).contains(r.display_name)
	# What it did sits on the Details tab.
	assert_str("\n".join(_texts(demo.readout.bot_details(r.bot_id)))).contains("Hit an enemy")
	assert_str(texts).contains("RANK UP")
	assert_str(texts).contains("+%.2f" % r.growth(Personality.ENDS.find("aggressive")))
	var grown: IconStat = panel.find_child("IconStat_trait_aggressive", true, false)
	assert_object(grown).is_not_null()
	# Generation 1, and its other spectrums grew too.
	assert_int(r.generation).is_equal(1)
	assert_float(r.growth(Personality.ENDS.find("reactive"))).is_greater(0.0)
	# The hexagon shows the new shape in full.
	var hex: PersonalityHexagon = panel.find_child("Chart", true, false)
	assert_float(hex.progress).is_equal(1.0)
	assert_array(hex.after).is_equal(r.personality_after)


func test_the_demo_has_a_tier_shift() -> void:
	var demo := (load("res://ui/post_fight/post_fight_demo.gd").new() as Control)
	var report: PostFightReport = demo.build_canned_report()
	var tiers := 0
	for b in report.bots:
		for c in b.level_ups():
			if c.is_tier_shift():
				tiers += 1
				assert_str(LevelUpCallout.title_for(c)).is_equal("MEGA OVERCHARGE SHOT!")
				assert_str(LevelUpCallout.rank_line(c)).is_equal("+5 -> MEGA")
				assert_str(LevelUpCallout.bonus_line(c)).is_equal("+ Pierce 50%")
	assert_int(tiers).is_equal(1)
	demo.free()


func _ranked(before_rank: String, after_rank: String, kind: String, v0: float, v1: float) -> SkillChange:
	var c := SkillChange.new()
	c.combat_skill_id = "heavy_strike"
	c.skill_name = "Overcharge Shot"
	c.ranked = true
	c.rank_before = before_rank
	c.rank_after = after_rank
	c.name_after = "Overcharge Shot " + after_rank
	c.level_before = 3
	c.level_after = 4
	c.stat_kind = kind
	c.value_before = v0
	c.value_after = v1
	c.cost_before = 4
	c.cost_after = 4
	c.uses_per_level = 12
	c.max_level = 13
	return c


func test_the_callout_shows_rank_and_numbers_before_and_after() -> void:
	var c := _ranked("+2", "+3", SkillNumbers.KIND_DAMAGE, 6.0, 7.0)
	assert_str(LevelUpCallout.one_line(c)).is_equal("OVERCHARGE SHOT +2 -> +3, 6 -> 7 dmg")
	c.cost_after = 3
	assert_str(LevelUpCallout.numbers_line(c)).is_equal("6 -> 7 dmg  ·  cost 4 -> 3")
	assert_str(LevelUpCallout.numbers_line(_ranked("", "+1", SkillNumbers.KIND_HEAL, 8.0, 8.5))).is_equal("8 -> 8.5 hp")
	assert_str(LevelUpCallout.numbers_line(_ranked("", "+1", SkillNumbers.KIND_GUARD, 50.0, 53.0))).is_equal("50 -> 53% guard")
	assert_str(LevelUpCallout.rank_line(_ranked("", "+1", SkillNumbers.KIND_HEAL, 8.0, 8.5))).is_equal("BASE -> +1")
	assert_str(Readout.skill_row_right(c)).is_equal("RANK UP +2 > +3 · 0/12")


func test_a_rank_up_shows_the_callout_and_skip_clears_it() -> void:
	var runner := scene_runner(DEMO)
	await runner.simulate_frames(1)
	var readout: Control = runner.scene().readout
	var guard := 0
	while readout.callout() == null and readout.is_tallying() and guard < 600:
		await runner.simulate_frames(1, 16)
		guard += 1
	var callout: LevelUpCallout = readout.callout()
	assert_object(callout).is_not_null()
	assert_str("\n".join(_texts(callout))).contains("->")
	readout.skip()
	assert_object(readout.callout()).is_null()
	assert_bool(readout.is_tallying()).is_false()


func test_the_hexagon_traces_the_outline_then_fills() -> void:
	var hex := PersonalityHexagon.new()
	hex.outline_share = 0.4
	hex.before = [0.2, 0.0, 0.0, 0.0, 0.0, 0.0] as Array[float]
	hex.after = [0.4, 0.0, 0.1, 0.0, 0.0, 0.0] as Array[float]
	hex.progress = 0.0
	assert_float(hex.outline_progress()).is_equal(0.0)
	assert_array(hex.filled_values()).is_equal(hex.before)
	hex.progress = 0.2
	assert_float(hex.outline_progress()).is_equal_approx(0.5, 1e-6)
	assert_float(hex.fill_progress()).is_equal(0.0)
	hex.progress = 0.7
	assert_float(hex.outline_progress()).is_equal(1.0)
	assert_float(hex.fill_progress()).is_equal_approx(0.5, 1e-6)
	# Only ever outward: every corner sits between the old and new values.
	for i in 6:
		assert_float(hex.filled_values()[i]).is_between(hex.before[i], hex.after[i])
	hex.progress = 1.0
	assert_array(hex.filled_values()).is_equal(hex.after)
	# The rim never shrinks below min_extent and never moves mid-growth.
	assert_float(hex.extent()).is_equal(0.5)
	hex.free()


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
	var row: Control = readout.bot_details(r.bot_id).find_child("Count_%s" % ActionTag.HIT_ENEMY, true, false)
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
	assert_str(texts).contains("RANK UP")
	assert_str(texts).contains("TIER UP")


## These tests' numbers were worked out under the old fight switches.
func before() -> void:
	Legacy.pin()


func after() -> void:
	Legacy.unpin()



func test_the_readout_has_summary_growth_and_details_tabs() -> void:
	var runner := scene_runner(DEMO)
	await runner.simulate_frames(2)
	var readout: Control = runner.scene().readout
	assert_array(readout.tabs.ids()).is_equal([&"summary", &"growth", &"details"])
	# The count-up plays on Growth, so it opens there.
	assert_str(str(readout.tabs.current)).is_equal("growth")


func test_each_bot_has_a_summary_card_with_three_headlines() -> void:
	var runner := scene_runner(DEMO)
	await runner.simulate_frames(2)
	var demo := runner.scene()
	demo.readout.skip()
	for r: BotFightReport in demo.report.bots:
		var card: InfoCard = demo.readout.find_child("Summary_%s" % r.bot_id, true, false)
		assert_object(card).is_not_null()
		assert_array(card.strip.kinds()).is_equal(["number", "chip", "pips"])
		assert_str(card.strip.headline(0).value_label.text).is_equal(str(r.decisions))
		var spec: Dictionary = demo.readout.summary_detail(r)
		assert_int((spec["sections"] as Array).size()).is_equal(3)
		for s: Dictionary in spec["sections"]:
			(s["content"] as Node).free()


func test_details_hold_what_each_bot_did() -> void:
	var runner := scene_runner(DEMO)
	await runner.simulate_frames(2)
	var demo := runner.scene()
	demo.readout.skip()
	for r: BotFightReport in demo.report.bots:
		var details: Control = demo.readout.bot_details(r.bot_id)
		for label: String in r.label_counts:
			if r.label_counts[label] > 0:
				assert_object(details.find_child("Count_%s" % label, true, false)).override_failure_message(label).is_not_null()
		assert_object(demo.readout.bot_panel(r.bot_id).find_child("Count_*", true, false)).is_null()
