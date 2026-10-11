extends GdUnitTestSuite
## RunTimeline: a readable timeline from journal lines, with act lengths
## against the target.


func _line(kind: String, play_s: float, extra: Dictionary = {}) -> Dictionary:
	var l := {"kind": kind, "play_s": play_s, "ts": "2026-10-11T14:00:00.000", "act": 0, "day": 1}
	l.merge(extra, true)
	return l


func _journal() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append(_line("run_start", 0.0, {"seed": 13, "squad_size": 3, "draft_size": 5, "variants": {}}))
	out.append(_line("draft_open", 1.0, {"offered": [{"id": "bot_1", "name": "Ash"}, {"id": "bot_2", "name": "Bolt"}]}))
	out.append(_line("draft_done", 40.0, {"picks": ["bot_2", "bot_1"], "seconds": 39.0}))
	out.append(_line("snapshot", 41.0, {"reason": "run_start", "regions_total": 12,
		"state": {"act": 0, "day": 1, "owned": ["a", "b"], "grid": 100.0, "energy": 5.0, "material": 3.0, "region_set_id": "lw12"}}))
	out.append(_line("action", 60.0, {"action": "wait"}))
	out.append(_line("action", 70.0, {"action": "attack", "region": "c", "region_name": "Bothell", "day": 2}))
	out.append(_line("fight_start", 70.0, {"fight": 1, "fight_kind": "attack", "territory_name": "Bothell", "level": 2, "seed": 9}))
	out.append(_line("command", 75.0, {"cmd": "select_skill", "arg": "strike", "problem": ""}))
	out.append(_line("command", 76.0, {"cmd": "select_target", "arg": "drone#1", "problem": "no"}))
	out.append(_line("fight_end", 150.0, {"outcome": "victory", "actions": 12, "seconds": 80.0, "grid_cost": 6.0}))
	out.append(_line("post_fight", 150.0, {"changes": {"bot_1": {"skill:Strike": [1, 2], "hp": [10, 12]}}}))
	out.append(_line("action", 1500.0, {"action": "act_zoom", "day": 100}))
	out.append(_line("run_end", 1600.0, {"won": false, "reason": "every region lost", "act": 1}))
	return out


func test_the_timeline_reads_the_run_in_order() -> void:
	var text := "\n".join(RunTimeline.lines(_journal()))
	assert_str(text).contains("RUN seed 13")
	assert_str(text).contains("DRAFT   picked Bolt, Ash (0m 39s)")
	assert_str(text).contains("── ACT 1 (lw12) ──")
	assert_str(text).contains("A1 D2     attack Bothell")
	assert_str(text).contains("-> VICTORY, 12 actions, 1m 20s real, 2 commands (1 refused)")
	assert_str(text).contains("Ash: Strike 1→2")
	assert_str(text).contains("END     LOST: every region lost")


func test_each_act_is_measured_against_the_target() -> void:
	var lines := RunTimeline.lines(_journal())
	var act := Array(lines).filter(func(l: String) -> bool: return l.begins_with("── ACT 1 done"))
	assert_int(act.size()).is_equal(1)
	# 41 s to 1500 s is 24 minutes: inside 10 to 30.
	assert_str(act[0]).contains("24m 19s real (target 10-30 min: on target)")
	assert_str(act[0]).contains("days 1-100")


func test_detail_lists_every_command() -> void:
	var text := "\n".join(RunTimeline.lines(_journal(), true))
	assert_str(text).contains("> select_target drone#1  (refused: no)")


func test_time_texts() -> void:
	assert_str(RunTimeline.clock_text(65.0)).is_equal("01:05")
	assert_str(RunTimeline.clock_text(3725.0)).is_equal("1:02:05")
	assert_str(RunTimeline.span_text(80.0)).is_equal("1m 20s")
	assert_str(RunTimeline.span_text(3900.0)).is_equal("1h 05m")
