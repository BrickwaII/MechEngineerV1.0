extends GdUnitTestSuite
## RunJournal: the line file, snapshots, command records and comparing.

const PATH := "user://run_journal_unit_test.jsonl"


func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func test_lines_append_with_numbers_and_read_back() -> void:
	var journal := RunJournal.new()
	assert_int(journal.open(PATH)).is_equal(OK)
	journal.write({"kind": "a", "x": 0.1 + 0.2})
	journal.write({"kind": "b"})
	journal.close()
	# Opening again carries on after the lines already there.
	journal.open(PATH)
	journal.write({"kind": "c"})
	journal.close()
	var lines := RunJournal.read_file(PATH)
	assert_array(lines.map(func(l: Dictionary) -> int: return int(l.seq))).is_equal([1, 2, 3])
	assert_array(lines.map(func(l: Dictionary) -> String: return str(l.kind))).is_equal(["a", "b", "c"])
	# Full precision: the number reads back exactly.
	assert_float(float(lines[0].x)).is_equal(0.1 + 0.2)


func test_a_broken_line_is_skipped() -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_line("{\"kind\": \"a\"}")
	file.store_line("{not json")
	file.store_line("{\"kind\": \"b\"}")
	file.close()
	assert_int(RunJournal.read_file(PATH).size()).is_equal(2)


func test_commands_round_trip() -> void:
	var commands: Array[FightCommand] = [FightCommand.select_bot("bot_1"), FightCommand.select_skill("strike"),
		FightCommand.select_target("drone#1"), FightCommand.wait("", 3), FightCommand.cancel()]
	for c in commands:
		var line: Dictionary = RunJournal.normalize(RunJournal.command_line(c, ""))
		var back := RunJournal.command_from(line)
		assert_int(back.kind).is_equal(c.kind)
		assert_str(back.arg).is_equal(c.arg)
		assert_int(back.ticks).is_equal(c.ticks)
	assert_object(RunJournal.command_from({"cmd": "dance"})).is_null()


func test_a_bot_snapshot_holds_stats_skills_and_every_personality_field() -> void:
	var bot := BotFactory.new(BotTuning.load_default()).build_draft(3)[0]
	bot.skills[0].level = 4
	var snap := RunJournal.bot_snapshot(bot)
	assert_str(str(snap.id)).is_equal(bot.id)
	assert_int(int(snap.stats.attack)).is_equal(bot.stats.attack)
	assert_int(int(snap.skills[0].level)).is_equal(4)
	for field in ["generation", "aggressive_defensive", "solitary_supportive", "reactive_methodical"]:
		assert_bool((snap.personality as Dictionary).has(field)).is_true()


func test_bot_changes_list_only_what_changed() -> void:
	var squad := BotFactory.new(BotTuning.load_default()).build_squad(3)
	var before: Dictionary = RunJournal.normalize(RunJournal.squad_snapshot(squad, null))
	var bot := squad.get_fielded()[0]
	bot.skills[0].level += 1
	bot.personality.aggressive_defensive += 0.25
	var changes := RunJournal.bot_changes(before, RunJournal.normalize(RunJournal.squad_snapshot(squad, null)))
	assert_array(changes.keys()).is_equal([bot.id])
	var mine: Dictionary = changes[bot.id]
	assert_array(mine.keys()).contains_exactly_in_any_order(
		["skill:%s" % bot.skills[0].display_name, "personality:aggressive_defensive"])


func test_differences_name_the_path_and_allow_rounding() -> void:
	var a := {"state": {"grid": 50.0, "owned": ["x", "y"]}, "n": 1}
	assert_array(RunJournal.differences(a, a.duplicate(true))).is_empty()
	var b := {"state": {"grid": 50.0000000001, "owned": ["x", "y"]}, "n": 1}
	assert_array(RunJournal.differences(a, b)).is_empty()
	var c := {"state": {"grid": 49.0, "owned": ["x"]}, "m": 2}
	var diffs := RunJournal.differences(a, c)
	assert_int(diffs.size()).is_equal(4)
	assert_str(diffs[0]).starts_with("m:")
	assert_str(diffs[1]).starts_with("n:")
	assert_str(diffs[2]).starts_with("state.grid:")
	assert_str(diffs[3]).starts_with("state.owned:")
