extends GdUnitTestSuite
## RunSave: the map state, the bots and the ledger in one resource file.

const PATH := "user://run_save_test.tres"


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
