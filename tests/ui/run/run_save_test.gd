extends GdUnitTestSuite
## RunSave: the map state, the bots and the ledger in one resource file.

const PATH := "user://run_save_test.res"


func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func _state() -> RunState:
	var state := RunState.new()
	state.region_set_id = "seattle"
	state.act = 1
	state.start_id = "north"
	state.owned = PackedStringArray(["a", "b"])
	state.pressure = {"a": 12.5, "b": 3.0}
	state.energy = 4.0
	state.material = 2.5
	state.time_points = 9
	state.grid = 77.0
	return state


func _save() -> RunSave:
	var squad := BotFactory.new(BotTuning.load_default()).build_squad(8)
	var ledger := SkillUseLedger.new()
	ledger.set_banked(squad.fielded_ids[0], "Strike", 2)
	return RunSave.make(42, squad, ledger, _state())


func test_round_trip() -> void:
	var save := _save()
	assert_int(save.save_file(PATH)).is_equal(OK)
	var loaded := RunSave.load_file(PATH)
	assert_object(loaded).is_not_null()
	assert_object(loaded).is_not_same(save)
	assert_int(loaded.run_seed).is_equal(42)
	assert_dict(loaded.run_state().to_dict()).is_equal(_state().to_dict())
	assert_array(Array(loaded.squad.fielded_ids)).is_equal(Array(save.squad.fielded_ids))
	assert_int(loaded.squad.bots.size()).is_equal(save.squad.bots.size())
	for i in save.squad.bots.size():
		var a := save.squad.bots[i]
		var b := loaded.squad.bots[i]
		assert_str(b.id).is_equal(a.id)
		assert_str(b.display_name).is_equal(a.display_name)
		assert_int(b.stats.attack).is_equal(a.stats.attack)
		assert_array(PersonalityDrift.values_of(b.personality)).is_equal(PersonalityDrift.values_of(a.personality))
	assert_dict(loaded.ledger.banked).is_equal(save.ledger.banked)


func test_a_broken_run_is_not_saved() -> void:
	var save := _save()
	save.squad.fielded_ids.append("nobody")
	assert_int(save.save_file(PATH)).is_equal(ERR_INVALID_DATA)
	assert_bool(FileAccess.file_exists(PATH)).is_false()


func test_a_missing_or_foreign_file_loads_as_null() -> void:
	assert_object(RunSave.load_file("user://no_such_run.tres")).is_null()
	ResourceSaver.save(SkillUseLedger.new(), PATH)
	assert_object(RunSave.load_file(PATH)).is_null()


func test_a_new_save_is_format_two() -> void:
	var save := _save()
	assert_int(save.version).is_equal(2)
	assert_int(save.save_file(PATH)).is_equal(OK)
	assert_int(RunSave.load_file(PATH).version).is_equal(2)


## A format-1 save (no version written, one signed value per personality
## spectrum, flat skill levels) converts as it loads: v splits into max(-v, 0)
## and max(v, 0), and flat level 10 becomes the highest rank no stronger.
func test_a_format_one_save_converts_as_it_loads() -> void:
	var path := "user://run_save_v1_test.tres"
	var save := _save()
	var bot := save.squad.bots[0]
	bot.personality = Personality.new(2)
	bot.skills[0].level = 10
	assert_int(ResourceSaver.save(save, path)).is_equal(OK)
	var text := FileAccess.get_file_as_string(path)
	assert_str(text).contains("version = 2")
	text = text.replace("version = 2\n", "").replace("generation = 2",
		"generation = 2\naggressive_defensive = -0.5\nreactive_methodical = 0.25")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	var loaded := RunSave.load_file(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	assert_object(loaded).is_not_null()
	assert_int(loaded.version).is_equal(2)
	var p := loaded.squad.bots[0].personality
	assert_array(p.get_ends()).is_equal([0.5, 0.0, 0.0, 0.0, 0.0, 0.25])
	var ranks := SkillRanks.load_default()
	var rank := loaded.squad.bots[0].skills[0].level
	assert_int(rank).is_equal(ranks.rank_for_flat_level(10, CombatTuning.load_default().power_percent_per_level))
	assert_int(rank).is_greater(1)
	# Other skills were at flat level 1 and stay at the base rank.
	assert_int(loaded.squad.bots[1].skills[0].level).is_equal(1)
