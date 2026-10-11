extends GdUnitTestSuite
## TallySequence: the post-fight count-up as timed steps.

const Demo := preload("res://ui/post_fight/post_fight_demo.gd")

var settings: GameSettings
var report: PostFightReport


func before_test() -> void:
	settings = GameSettings.new()
	var demo: Control = auto_free(Demo.new())
	report = demo.build_canned_report()


func _kinds(tally: TallySequence) -> Array:
	return tally.steps.map(func(s: TallySequence.Step) -> String: return s.kind)


func test_bots_play_one_after_another_with_the_payoffs_last() -> void:
	var tally := TallySequence.new(report, settings)
	var kinds := _kinds(tally)
	assert_str(kinds[0]).is_equal("bot")
	assert_int(kinds.count("bot")).is_equal(report.bots.size())
	assert_int(kinds.count("gap")).is_equal(report.bots.size() - 1)
	# Bot indices never go back.
	var last := 0
	for step in tally.steps:
		assert_int(step.bot).is_greater_equal(last)
		last = step.bot
	# Each bot: counters and skills, then its personality growth last.
	for b in report.bots.size():
		var mine := tally.steps.filter(func(s: TallySequence.Step) -> bool: return s.bot == b and s.kind != "gap")
		var seen_grow := false
		for step: TallySequence.Step in mine:
			if step.kind == "grow":
				seen_grow = true
			else:
				assert_bool(seen_grow).override_failure_message("%s after the growth" % step.kind).is_false()


func test_level_ups_and_personality_growth_get_their_own_step() -> void:
	var tally := TallySequence.new(report, settings)
	var level_ups := 0
	var grew := 0
	for r in report.bots:
		level_ups += r.level_ups().size()
		if r.personality_grew():
			grew += 1
	assert_int(level_ups).is_greater(0)
	assert_int(_kinds(tally).count("level_up")).is_equal(level_ups)
	assert_int(_kinds(tally).count("grow")).is_equal(grew)


func test_a_tier_shift_holds_longer_than_a_rank_step() -> void:
	var tally := TallySequence.new(report, settings)
	var rank_ms := 0.0
	var tier_ms := 0.0
	for step in tally.steps:
		if step.kind == "level_up":
			if step.change.is_tier_shift():
				tier_ms = step.duration
			else:
				rank_ms = step.duration
	assert_float(rank_ms).is_greater(0.0)
	assert_float(tier_ms).is_greater(rank_ms)


func test_counts_tick_up_and_every_step_starts_once() -> void:
	var tally := TallySequence.new(report, settings)
	var count_index := _kinds(tally).find("count")
	var started: Array[int] = []
	while not tally.is_done():
		started.append_array(tally.advance(1.0 / 60.0))
		if tally.current == count_index:
			assert_int(tally.shown_count(count_index)).is_between(0, tally.steps[count_index].to)
	assert_array(started).is_equal(range(tally.steps.size()))
	assert_int(tally.shown_count(count_index)).is_equal(tally.steps[count_index].to)


func test_a_count_row_takes_its_steps_within_the_caps() -> void:
	var tally := TallySequence.new(report, settings)
	for step in tally.steps:
		if step.kind in ["count", "skill"]:
			assert_float(step.duration * 1000.0).is_between(ScreenFeel.number("readout.row_in_ms") - 0.01,
				ScreenFeel.number("readout.count_max_ms") + 0.01)


func test_skip_finishes_and_reports_the_steps_not_started() -> void:
	var tally := TallySequence.new(report, settings)
	var first := tally.advance(0.0)
	assert_array(first).is_equal([0])
	var rest := tally.skip()
	assert_bool(tally.is_done()).is_true()
	assert_int(rest.size()).is_equal(tally.steps.size() - 1)
	assert_float(tally.progress(tally.steps.size() - 1)).is_equal(1.0)
	assert_array(tally.advance(1.0)).is_empty()


func test_animation_speed_scales_the_tally_and_skip_makes_it_instant() -> void:
	var normal := TallySequence.new(report, settings).total_seconds()
	settings.animation_speed = "2x"
	assert_float(TallySequence.new(report, settings).total_seconds()).is_equal_approx(normal / 2.0, 1e-6)
	settings.animation_speed = "skip"
	var instant := TallySequence.new(report, settings)
	assert_float(instant.total_seconds()).is_equal(0.0)
	instant.advance(0.0)
	assert_bool(instant.is_done()).is_true()


func test_an_error_report_has_no_steps() -> void:
	var bad := PostFightReport.new()
	bad.error = "no"
	assert_bool(TallySequence.new(bad, settings).is_done()).is_true()
