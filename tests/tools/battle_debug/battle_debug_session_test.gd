extends GdUnitTestSuite
## BattleDebugSession, the battle debug simulator's engine (combat rework
## S9b): live edits, rewind, restart, forced states, Simulate, Save to data.
## Plays the S8 sandbox (archetype enemies, statuses, plating) so snapshots
## carry every kind of fight state.

const SANDBOX := "res://data/scenarios/sandbox_3v3.json"
const DIR := "user://battle_debug_session_test"


func before_test() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	JsonFile.clear_cache()


func after_test() -> void:
	for file in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(file))
	DirAccess.remove_absolute(DIR)
	JsonFile.clear_cache()


## Settings whose Save to data writes copies of the shipped files in DIR.
func _settings() -> BattleDebugSettings:
	var actions := DIR.path_join("actions.json")
	var weights := DIR.path_join("intent_weights.json")
	JsonFile.write_text(actions, FileAccess.get_file_as_string("res://data/combat/actions.json"))
	JsonFile.write_text(weights, FileAccess.get_file_as_string("res://data/combat/intent/intent_weights.json"))
	return BattleDebugSettings.from_dict({
		"simulate_runs": 3, "simulate_policies": ["greedy", "smart"],
		"data_files": {"actions": actions, "intent_weights": weights},
		"export_dir": DIR, "max_snapshots": 500,
	})


func _fight(seed_value := 5) -> Fight:
	var r := ScenarioFiles.load_scenario(SANDBOX).resolve()
	assert_array(r.problems).is_empty()
	return Fight.new(r.request, seed_value, r.tuning, r.enemy_table)


func _session(seed_value := 5) -> BattleDebugSession:
	var dbg := BattleDebugSession.new(_fight(seed_value), null, null, null, _settings())
	dbg.advance()
	return dbg


func _state(dbg: BattleDebugSession) -> Dictionary:
	return FightSnapshot.state_of(dbg.fight)


## Steps until a squad bot holding heavy_strike is the one to act, with the
## energy to use it; returns that bot.
func _to_heavy_strike_turn(dbg: BattleDebugSession) -> Combatant:
	for i in 60:
		var actor := dbg.advance()
		if actor == null:
			break
		if actor.side == Combatant.Side.PLAYER and actor.has_skill("heavy_strike"):
			dbg.set_unit_field(actor.id, "energy", actor.stats.battery_capacity)
			return actor
		dbg.step()
	fail("no squad bot with heavy_strike got a turn")
	return null


## The gauge `actor` is left with after a Heavy Strike on the first enemy,
## tried on a copy of the fight.
func _gauge_after_heavy(dbg: BattleDebugSession, actor: Combatant) -> int:
	var copy := FightCopy.of(dbg.fight)
	var foe := copy.living(Combatant.Side.ENEMY)[0]
	assert_str(copy.submit(FightAction.use("heavy_strike", foe.id))).is_empty()
	return copy.combatant(actor.id).gauge


func test_rewind_restores_the_exact_state() -> void:
	var dbg := _session()
	var states := {}
	for i in 12:
		states[dbg.fight.action_count] = _state(dbg)
		if not dbg.step():
			break
	dbg.run()
	var final_lines := FightLog.lines(dbg.fight.events)
	assert_bool(dbg.fight.is_over()).is_true()
	var points := dbg.snapshot_points()
	var back: int = points[4]
	assert_str(dbg.rewind_to(back)).is_empty()
	assert_dict(_state(dbg)).is_equal(states[back])
	assert_int(dbg.snapshot_points().max()).is_equal(back)
	# Played on, the fight comes out exactly as it did the first time.
	dbg.run()
	assert_array(Array(FightLog.lines(dbg.fight.events))).is_equal(Array(final_lines))


func test_rewind_keeps_the_same_unit_objects() -> void:
	var dbg := _session()
	var units := dbg.fight.combatants.duplicate()
	dbg.run(6)
	dbg.rewind_to(dbg.snapshot_points()[1])
	assert_bool(dbg.roster_replaced).is_false()
	for i in units.size():
		assert_object(dbg.fight.combatants[i]).is_same(units[i])
	assert_object(dbg.fight.timeline.units).is_same(dbg.fight.combatants)


func test_restart_plays_the_same_seed_from_the_start() -> void:
	var dbg := _session()
	var start := _state(dbg)
	dbg.run(8)
	dbg.set_unit_field(dbg.fight.combatants[0].id, "hp", 1)
	assert_str(dbg.restart()).is_empty()
	assert_dict(_state(dbg)).is_equal(start)
	assert_array(dbg.snapshot_points()).is_equal([0])


func test_a_unit_edit_made_at_a_decision_survives_a_rewind_to_it() -> void:
	var dbg := _session()
	dbg.run(3)
	var at := dbg.fight.action_count
	var bot := dbg.fight.living(Combatant.Side.PLAYER)[0]
	dbg.set_unit_field(bot.id, "attack", 30)
	dbg.run(4)
	dbg.set_unit_field(bot.id, "defense", 40)
	dbg.rewind_to(at)
	assert_int(bot.stats.attack).is_equal(30)
	assert_int(bot.stats.defense).is_not_equal(40)
	var later := dbg.changes.filter(func(c: DebugChange) -> bool: return c.field == "defense")
	assert_bool((later[0] as DebugChange).undone).is_true()


func test_an_action_edit_reaches_every_holder_and_survives_rewind() -> void:
	var dbg := _session()
	var actor := _to_heavy_strike_turn(dbg)
	var at := dbg.fight.action_count
	var short := _gauge_after_heavy(dbg, actor)
	assert_str(dbg.set_action_field("heavy_strike", "recovery", 90)).is_empty()
	for c in dbg.fight.combatants:
		if c.has_skill("heavy_strike"):
			assert_int(c.skill("heavy_strike").recovery).is_equal(90)
	var long := _gauge_after_heavy(dbg, actor)
	assert_int(long).is_less(short)
	dbg.step()
	dbg.rewind_to(at)
	assert_int(actor.skill("heavy_strike").recovery).is_equal(90)
	# The shipped tuning is untouched.
	assert_int(CombatTuning.load_default().skills["heavy_strike"].recovery).is_equal(30)


func test_a_definition_that_would_not_validate_is_refused() -> void:
	var dbg := _session()
	assert_str(dbg.set_action_field("heavy_strike", "hit_count", 0)).is_not_empty()
	assert_str(dbg.set_action_field("heavy_strike", "recovery", "lots")).is_not_empty()
	assert_str(dbg.set_action_field("nope", "recovery", 1)).is_not_empty()
	assert_int(dbg.action("heavy_strike").hit_count).is_equal(1)
	assert_array(dbg.changes).is_empty()


func test_done_when_heavy_strike_recovery_edit_rewind_simulate_and_save() -> void:
	var dbg := _session()
	var actor := _to_heavy_strike_turn(dbg)
	var at := dbg.fight.action_count
	var foe := dbg.fight.living(Combatant.Side.ENEMY)[0].id
	# Value one: 60.
	dbg.set_action_field("heavy_strike", "recovery", 60)
	var gauge_60 := _gauge_after_heavy(dbg, actor)
	assert_str(dbg.submit(FightAction.use("heavy_strike", foe))).is_empty()
	# Rewind the turn, try value two: 10.
	assert_str(dbg.rewind_one()).is_empty()
	assert_int(dbg.fight.action_count).is_equal(at)
	dbg.set_action_field("heavy_strike", "recovery", 10)
	assert_int(_gauge_after_heavy(dbg, actor)).is_greater(gauge_60)
	assert_str(dbg.submit(FightAction.use("heavy_strike", foe))).is_empty()
	# Measure the edited version.
	var cmp := dbg.simulate()
	assert_array(cmp.problems).is_empty()
	assert_int(cmp.row("greedy").fights).is_equal(3)
	assert_int(cmp.row("smart").fights).is_equal(3)
	assert_str(cmp.format_text()).is_not_empty()
	# Keep the winner: one data change, shown as a one-line diff, then saved.
	var patch := dbg.preview_save()
	assert_array(patch.problems).is_empty()
	assert_int(patch.files.size()).is_equal(1)
	assert_str(patch.diff_text()).contains("\"recovery\": 10")
	assert_str(patch.diff_text()).contains("\"recovery\": 30")
	assert_array(dbg.save_to_data()).is_empty()
	var reloaded := ActionTable.load_file(dbg.data_paths["actions"])
	assert_int(reloaded.actions["heavy_strike"].recovery).is_equal(10)
	assert_array(reloaded.validate()).is_empty()
	assert_bool(dbg.preview_save().is_empty()).is_true()


func test_saved_ai_weights_reload() -> void:
	var dbg := _session()
	assert_str(dbg.set_ai_weight("kill", "base", 7.5)).is_empty()
	assert_str(dbg.set_ai_weight("heal", "reactive_methodical", 0.25)).is_empty()
	assert_float(dbg.planner.weights.value("kill", "base")).is_equal(7.5)
	assert_array(dbg.save_to_data()).is_empty()
	var w := IntentWeights.load_file(dbg.data_paths["intent_weights"])
	assert_float(w.value("kill", "base")).is_equal(7.5)
	assert_float(w.value("heal", "reactive_methodical")).is_equal(0.25)
	assert_float(IntentWeights.load_default().value("kill", "base")).is_equal(3.0)


func test_only_chosen_changes_are_saved_and_a_return_to_the_file_value_writes_nothing() -> void:
	var dbg := _session()
	dbg.set_action_field("strike", "power_percent", 120)
	dbg.set_action_field("shred", "energy_cost", 3)
	dbg.set_action_field("shred", "energy_cost", 2)
	var strike_seq := dbg.changes[0].seq
	var only: Array[int] = [strike_seq]
	var patch := dbg.preview_save(only)
	assert_array(patch.seqs()).is_equal(only)
	assert_array(dbg.save_to_data(only)).is_empty()
	var text := FileAccess.get_file_as_string(dbg.data_paths["actions"])
	assert_str(text).contains("\"strike\": {\"name\": \"Strike\", \"energy_cost\": 1, \"power_percent\": 120}")
	assert_str(text).contains("\"shred\": {\"name\": \"Shred\", \"energy_cost\": 2,")
	assert_bool(dbg.preview_save().is_empty()).is_true()


func test_setting_a_default_on_a_key_the_file_leaves_out_writes_nothing() -> void:
	var dbg := _session()
	dbg.set_action_field("strike", "recovery", 20)
	dbg.set_action_field("strike", "recovery", 0)
	assert_bool(dbg.preview_save().is_empty()).is_true()


func test_unit_edits_rederive_and_clamp() -> void:
	var dbg := _session()
	var bot := dbg.fight.living(Combatant.Side.PLAYER)[0]
	var old_stats := bot.stats
	dbg.set_unit_field(bot.id, "speed", 11)
	assert_int(bot.charge_per_tick).is_equal(SpeedRules.charge_per_tick(11, dbg.tuning))
	assert_object(bot.stats).is_not_same(old_stats)
	dbg.set_unit_field(bot.id, "battery", 3)
	assert_int(bot.energy()).is_less_equal(3)
	dbg.set_unit_field(bot.id, "hp", 9999)
	assert_int(bot.hp).is_equal(bot.max_hp)
	assert_str(dbg.set_unit_field(bot.id, "luck", 3)).is_not_empty()


func test_statuses_plating_and_personality_can_be_forced() -> void:
	var dbg := _session()
	var foe := dbg.fight.living(Combatant.Side.ENEMY)[0]
	assert_str(dbg.apply_status(foe.id, "exposed")).is_empty()
	assert_bool(foe.has_status("exposed")).is_true()
	assert_str(dbg.remove_status(foe.id, "exposed")).is_empty()
	assert_bool(foe.has_status("exposed")).is_false()
	dbg.set_unit_field(foe.id, "plating", 9)
	assert_int(foe.plating).is_equal(9)
	assert_int(foe.max_plating).is_equal(9)
	dbg.set_personality(foe.id, "aggressive", 2.0)
	assert_float(dbg.personality(foe.id).aggressive).is_equal(2.0)
	var other := dbg.fight.living(Combatant.Side.ENEMY)[1]
	assert_float(dbg.personality(other.id).aggressive).is_not_equal(2.0)


func test_a_forced_action_is_played_on_the_units_turn() -> void:
	var dbg := _session()
	var foes := dbg.fight.living(Combatant.Side.ENEMY).filter(func(c: Combatant) -> bool: return c.has_skill("strike"))
	assert_array(foes).is_not_empty()
	var foe: Combatant = foes[0]
	var bot := dbg.fight.living(Combatant.Side.PLAYER)[0]
	dbg.set_unit_field(foe.id, "energy", foe.stats.battery_capacity)
	assert_str(dbg.give_turn(foe.id)).is_empty()
	assert_object(dbg.fight.pending_actor).is_same(foe)
	assert_str(dbg.force_action(foe.id, FightAction.use("strike", bot.id))).is_empty()
	dbg.step()
	assert_str(dbg.fight.action_tags[-1]).is_equal("%s:strike" % foe.id)
	assert_object(dbg.forced_action(foe.id)).is_null()


func test_units_can_be_added_removed_and_rewound() -> void:
	var dbg := _session()
	var at := dbg.fight.action_count
	var count := dbg.fight.combatants.size()
	assert_str(dbg.add_enemy("plated_medium")).is_empty()
	assert_int(dbg.fight.combatants.size()).is_equal(count + 1)
	assert_object(dbg.fight.combatant(dbg.last_added_id)).is_not_null()
	assert_str(dbg.copy_unit(dbg.fight.combatants[0].id)).is_empty()
	assert_int(dbg.fight.combatants.size()).is_equal(count + 2)
	dbg.step()
	var gone := dbg.fight.living(Combatant.Side.ENEMY)[0].id
	assert_str(dbg.remove_unit(gone)).is_empty()
	assert_object(dbg.fight.combatant(gone)).is_null()
	assert_bool(dbg.fight.is_awaiting_decision() or dbg.fight.is_over()).is_true()
	dbg.rewind_to(at)
	assert_bool(dbg.roster_replaced).is_true()
	assert_int(dbg.fight.combatants.size()).is_equal(count + 2)
	assert_object(dbg.fight.combatant(gone)).is_not_null()


func test_simulate_plays_the_edited_lineup() -> void:
	var dbg := _session()
	for foe in dbg.fight.living(Combatant.Side.ENEMY):
		dbg.set_unit_field(foe.id, "max_hp", 1)
		dbg.set_unit_field(foe.id, "attack", 0)
	var r := dbg.simulation_setup()
	assert_array(r.problems).is_empty()
	assert_int(r.request.squad.size()).is_equal(3)
	var names: Array[String] = ["greedy"]
	var cmp := dbg.simulate(2, names)
	assert_int(cmp.row("greedy").wins).is_equal(2)


func test_export_writes_every_change_and_the_diff() -> void:
	var dbg := _session()
	dbg.set_action_field("heavy_strike", "recovery", 45)
	dbg.set_unit_field(dbg.fight.combatants[0].id, "hp", 5)
	var path := dbg.export_tuning_diff()
	assert_str(path).is_not_empty()
	var doc: Dictionary = JsonFile.read_object(path)
	assert_int((doc.log as Array).size()).is_equal(2)
	assert_int((doc.data_changes as Array).size()).is_equal(1)
	assert_str(str(doc.diffs.values()[0])).contains("\"recovery\": 45")
	assert_str(dbg.log_text()).contains("heavy_strike.recovery: 30 -> 45")


func test_settings_file_is_valid() -> void:
	assert_array(BattleDebugSettings.load_default().validate()).is_empty()
