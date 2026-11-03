extends GdUnitTestSuite
## The battle debugger panel (S9b) on a live battle screen: edits through its
## editors reach the fight and the screen redraws; pause holds enemy turns;
## rewind, add and remove keep the screen in step.

const Helpers := preload("res://tests/ui/fight/fight_ui_helpers.gd")
const BATTLE_SCENE := preload("res://ui/fight/battle_screen.tscn")
const SANDBOX := "res://data/scenarios/sandbox_3v3.json"
const DIR := "user://battle_debugger_test"

var _runner: GdUnitSceneRunner
var _screen: BattleScreen
var _dbg: BattleDebugger


func after_test() -> void:
	for file in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(file))
	DirAccess.remove_absolute(DIR)
	JsonFile.clear_cache()


func _settings() -> BattleDebugSettings:
	DirAccess.make_dir_recursive_absolute(DIR)
	var actions := DIR.path_join("actions.json")
	JsonFile.write_text(actions, FileAccess.get_file_as_string("res://data/combat/actions.json"))
	var weights := DIR.path_join("intent_weights.json")
	JsonFile.write_text(weights, FileAccess.get_file_as_string("res://data/combat/intent/intent_weights.json"))
	return BattleDebugSettings.from_dict({"simulate_runs": 2, "simulate_policies": ["greedy", "smart"],
		"data_files": {"actions": actions, "intent_weights": weights}, "export_dir": DIR})


func _open() -> void:
	var r := ScenarioFiles.load_scenario(SANDBOX).resolve()
	_screen = BATTLE_SCENE.instantiate()
	_screen.setup(r.request, 5, Helpers.fast_tuning(), r.tuning, r.enemy_table)
	_runner = scene_runner(auto_free(_screen))
	await _runner.simulate_frames(1)
	_dbg = BattleDebugger.attach(_screen, true, _settings())
	await _runner.simulate_frames(1)
	_dbg.visible = true
	await _runner.simulate_frames(1)


func test_attach_shares_the_fight_and_wraps_the_enemy_policy() -> void:
	await _open()
	assert_object(_dbg.session.fight).is_same(_screen.fight)
	assert_object(_screen.handler.enemy_policy).is_same(_dbg.session.enemy_policy)
	assert_object(_screen.telegraph.planner).is_same(_dbg.session.planner)
	assert_bool(_screen.hold_enemy_turns).is_true()
	assert_bool(_screen.inspect_enabled).is_true()


func test_paused_enemies_wait_and_step_plays_one_decision() -> void:
	await _open()
	var before := _screen.fight.action_count
	await _runner.simulate_frames(5)
	if _screen.handler.is_enemy_turn():
		assert_int(_screen.fight.action_count).is_equal(before)
	_dbg.step()
	await _runner.simulate_frames(1)
	assert_int(_screen.fight.action_count).is_equal(before + 1)
	assert_array(_dbg.session.snapshot_points()).contains([before + 1])


func test_an_action_edit_in_its_editor_reaches_the_fight() -> void:
	await _open()
	_dbg.inspect_action("heavy_strike")
	var spin: SpinBox = _dbg.action_editors["recovery"]
	spin.value = 75
	await _runner.simulate_frames(1)
	for c in _screen.fight.combatants:
		if c.has_skill("heavy_strike"):
			assert_int(c.skill("heavy_strike").recovery).is_equal(75)
	assert_str(_dbg.changes_label.text).contains("heavy_strike.recovery: 30 -> 75")
	assert_int(_dbg.save_checks.size()).is_equal(1)


func test_unit_edit_rewind_and_roster_changes_keep_the_screen_in_step() -> void:
	await _open()
	var at := _screen.fight.action_count
	var bot := _screen.fight.living(Combatant.Side.PLAYER)[0]
	_dbg.inspect_unit(bot.id)
	(_dbg.unit_editors["hp"] as SpinBox).value = 3
	await _runner.simulate_frames(1)
	assert_int(bot.hp).is_equal(3)
	_dbg.step()
	_dbg.step()
	await _runner.simulate_frames(1)
	assert_str(_dbg.session.add_enemy("plated_medium")).is_empty()
	await _runner.simulate_frames(1)
	assert_bool(_screen.unit_panels.has(_dbg.session.last_added_id)).is_true()
	_dbg.rewind_to(at)
	await _runner.simulate_frames(1)
	assert_int(_screen.fight.action_count).is_equal(at)
	assert_int(_screen.unit_panels.size()).is_equal(_screen.fight.combatants.size())
	# The roster changed since, so the units are new objects: look it up again.
	assert_bool(_dbg.session.roster_replaced).is_true()
	assert_int(_screen.fight.combatant(bot.id).hp).is_equal(3)


func test_simulate_and_save_from_the_panel() -> void:
	await _open()
	_dbg.inspect_action("heavy_strike")
	(_dbg.action_editors["recovery"] as SpinBox).value = 10
	var cmp := _dbg.simulate()
	assert_array(cmp.problems).is_empty()
	assert_str(_dbg.sim_label.text).contains("Action use")
	var patch := _dbg.show_save_diff()
	assert_str(patch.diff_text()).contains("\"recovery\": 10")
	_dbg.save_dialog.hide()
	assert_array(_dbg.save_checked()).is_empty()
	assert_int(ActionTable.load_file(DIR.path_join("actions.json")).actions["heavy_strike"].recovery).is_equal(10)
