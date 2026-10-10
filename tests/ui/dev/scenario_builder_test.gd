extends GdUnitTestSuite

var _builder: Control
var _dir: String
var _test_number := 0


func before_test() -> void:
	# Temp dirs last for the whole suite, so each test gets its own.
	_test_number += 1
	_dir = create_temp_dir("scenario_builder_%d" % _test_number)
	var tuning := BotTuning.load_default()
	var hammer := BotLibrary.new_bot(tuning, "hammer", "Hammer")
	hammer.stats.attack = 9
	BotLibrary.save_bot(hammer, _dir.path_join("bots"), tuning)
	var boss := BotLibrary.new_bot(tuning, "boss", "Boss")
	boss.stats.hp = 30
	boss.hp = 30
	BotLibrary.save_bot(boss, _dir.path_join("enemies"), tuning)
	_builder = auto_free(load("res://ui/dev/scenario_builder.tscn").instantiate())
	_builder.bot_dir = _dir.path_join("bots")
	_builder.enemy_dir = _dir.path_join("enemies")
	_builder.scenario_dir = _dir.path_join("scenarios")
	_builder.log_path = _dir.path_join("stats.jsonl")
	add_child(_builder)


func _fill_form() -> void:
	_builder._name_edit.text = "Hammer and draft vs boss"
	_builder._level_spin.value = 2
	_builder.add_squad_entry({"squad_file": BotLibrary.path_for(_builder.bot_dir, "hammer")})
	_builder.add_squad_entry({"draft_seed": 2024})
	_builder.add_enemy_entry({"squad_file": BotLibrary.path_for(_builder.enemy_dir, "boss")})
	_builder.add_enemy_entry({"enemy": "rust_hound", "count": 2})


func test_saved_bots_and_enemies_are_offered() -> void:
	var squad_items := []
	for i in _builder._squad_source.item_count:
		squad_items.append(_builder._squad_source.get_item_text(i))
	assert_array(squad_items).contains(["Saved bot: Hammer (hammer)", "Saved enemy: Boss (boss)"])
	var enemy_items := []
	for i in _builder._enemy_source.item_count:
		enemy_items.append(_builder._enemy_source.get_item_text(i))
	assert_array(enemy_items).contains(["Enemy table: Rust Hound", "Saved enemy: Boss (boss)"])


func test_a_saved_scenario_loads_back_the_same() -> void:
	_fill_form()
	var path: String = _builder.save()
	assert_str(path).is_equal(_builder.scenario_dir.path_join("hammer_and_draft_vs_boss.json"))
	var loaded := ScenarioFiles.load_scenario(path)
	assert_str(loaded.scenario_name).is_equal("Hammer and draft vs boss")
	assert_int(loaded.defense_level).is_equal(2)
	assert_int(loaded.squad_entries.size()).is_equal(2)
	assert_int(loaded.enemy_entries.size()).is_equal(2)
	var r := loaded.resolve()
	assert_array(r.problems).is_empty()
	assert_str(r.request.squad[0].id).is_equal("hammer")
	# And it shows in the form again after a reset.
	_builder.clear_entries()
	assert_bool(_builder.load_file(path)).is_true()
	assert_str(JSON.stringify(_builder.scenario_from_form().to_dict(), "", true)) \
		.is_equal(JSON.stringify(loaded.to_dict(), "", true))


func test_an_unplayable_scenario_is_not_saved() -> void:
	_builder._name_edit.text = "Empty"
	assert_str(_builder.save()).is_empty()
	assert_str(_builder._status.text).contains("scenario fields no squad")


func test_running_from_the_screen_matches_the_batch_simulator() -> void:
	_fill_form()
	_builder.set_run_options(15, 4, false)
	var report: BatchReport = _builder.run_batch()
	var direct := BatchSimulator.run(_builder.scenario_from_form(), 15, 4)
	assert_int(report.runs).is_equal(15)
	assert_int(report.wins).is_equal(direct.wins)
	assert_float(report.actions.mean).is_equal(direct.actions.mean)
	assert_str(_builder.report_text()).contains("Win rate:")
	assert_bool(FileAccess.file_exists(_builder.log_path)).is_false()


func test_a_run_with_logging_on_appends_records() -> void:
	_fill_form()
	_builder.set_run_options(6, 1, true)
	_builder.run_batch()
	assert_int(FightStatsLog.read_all(_builder.log_path).size()).is_equal(6)


func test_a_sample_scenario_loads_and_runs() -> void:
	assert_bool(_builder.load_file("res://data/scenarios/duo_vs_turret.json")).is_true()
	_builder.set_run_options(5, 1, false)
	assert_array((_builder.run_batch() as BatchReport).problems).is_empty()
