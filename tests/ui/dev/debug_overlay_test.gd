extends GdUnitTestSuite


func _fight(seed_value := 1) -> SimulatedFight:
	return ScenarioFiles.load_scenario("res://data/scenarios/level2_drafted_squad.json").resolve().start(seed_value)


## Everything about the fight the overlay could change.
func _state(fight: Fight) -> Array:
	return [fight.log_text(), fight.timeline.current_tick, fight.action_count, fight.pending_actor,
		fight.combatants.map(func(c: Combatant) -> Array:
			return [c.hp, c.gauge, c.energy_milli, c.wait_target_milli, c.wait_ticks])]


func test_the_snapshot_shows_each_units_stats_energy_and_gauge() -> void:
	var sim := _fight()
	sim.step()
	sim.step()
	sim.fight.advance()
	var snap := DebugOverlay.snapshot(sim.fight, 5)
	assert_int(snap.units.size()).is_equal(sim.fight.combatants.size())
	for i in sim.fight.combatants.size():
		var c := sim.fight.combatants[i]
		var u: Dictionary = snap.units[i]
		assert_str(u.name).is_equal(c.display_name)
		assert_str(u.hp_text).is_equal("%d/%d" % [c.hp, c.max_hp])
		assert_int(u.speed).is_equal(c.stats.speed)
		assert_str(u.gauge_text).is_equal("%d/%d" % [c.gauge, sim.fight.tuning.action_threshold])
		assert_str(u.energy_text).starts_with("%.1f/" % (c.energy_milli / 1000.0))
	assert_str(snap.header).contains("action 2")
	assert_str(snap.header).contains("waiting on " + sim.fight.pending_actor.display_name)


func test_the_snapshot_timeline_matches_the_fight_preview() -> void:
	var sim := _fight()
	sim.fight.advance()
	var snap := DebugOverlay.snapshot(sim.fight, 6)
	var preview := sim.fight.upcoming(6)
	assert_int(snap.timeline.size()).is_equal(6)
	for i in 6:
		assert_str(snap.timeline[i]).starts_with("%s @%d" % [preview[i].display_name, preview[i].tick])


func test_the_overlay_never_changes_the_fight() -> void:
	var sim := _fight(3)
	sim.step()
	sim.fight.advance()
	var before := _state(sim.fight)
	var overlay: DebugOverlay = auto_free(DebugOverlay.new())
	add_child(overlay)
	overlay.fight = sim.fight
	overlay.refresh()
	DebugOverlay.snapshot(sim.fight, 20)
	assert_that(_state(sim.fight)).is_equal(before)


func test_the_overlay_updates_as_the_fight_moves_on() -> void:
	var sim := _fight()
	var overlay: DebugOverlay = auto_free(DebugOverlay.new())
	add_child(overlay)
	overlay.fight = sim.fight
	var first: String = overlay._header.text
	sim.step()
	sim.step()
	overlay.refresh()
	assert_str(overlay._header.text).is_not_equal(first)
	assert_str(overlay._header.text).contains("action 2")
	# One header row plus one row per unit.
	assert_int(overlay._grid.get_child_count()).is_equal(DebugOverlay.COLUMNS.size() * (sim.fight.combatants.size() + 1))


func test_intents_come_from_the_intent_source_when_one_is_set() -> void:
	var sim := _fight()
	var no_source := DebugOverlay.snapshot(sim.fight, 3)
	assert_str(no_source.units[-1].intent).is_equal(DebugOverlay.NO_INTENT)
	var source := func(_f: Fight, unit: Combatant) -> String: return "strike " + unit.id
	var with_source := DebugOverlay.snapshot(sim.fight, 3, source)
	var enemy: Dictionary = with_source.units[-1]
	assert_str(enemy.intent).is_equal("strike " + enemy.id)
	assert_str(with_source.units[0].intent).is_equal(DebugOverlay.NO_INTENT)


func test_by_default_the_overlay_shows_each_enemys_planned_intent() -> void:
	var sim := _fight()
	sim.fight.advance()
	var overlay: DebugOverlay = auto_free(DebugOverlay.new())
	add_child(overlay)
	overlay.fight = sim.fight
	var planner := IntentPlanner.new()
	var enemy := sim.fight.living(Combatant.Side.ENEMY)[0]
	var expected := DebugOverlay.planned_intent(planner, sim.fight, enemy)
	var intent := planner.plan(sim.fight, enemy)
	assert_str(expected).starts_with(intent.kind_name())
	assert_str(expected).contains(sim.fight.combatant(intent.target_id()).display_name)
	var row: Array = overlay._cells[enemy.id]
	assert_str((row[DebugOverlay.COLUMNS.find("Intent")] as Label).text).is_equal(expected)
	var ally_row: Array = overlay._cells[sim.fight.combatants[0].id]
	assert_str((ally_row[DebugOverlay.COLUMNS.find("Intent")] as Label).text).is_equal(DebugOverlay.NO_INTENT)


func test_no_fight_shows_an_empty_overlay() -> void:
	var snap := DebugOverlay.snapshot(null, 5)
	assert_array(snap.units).is_empty()
	var overlay: DebugOverlay = auto_free(DebugOverlay.new())
	add_child(overlay)
	overlay.refresh()
	assert_str(overlay._header.text).contains("no fight")


func test_the_demo_plays_a_fight_with_the_overlay_attached() -> void:
	var demo: Control = auto_free(load("res://ui/dev/debug_overlay_demo.tscn").instantiate())
	add_child(demo)
	demo.set_process(false)
	assert_object(demo.overlay.fight).is_same(demo.sim.fight)
	for i in 3:
		demo.step()
	assert_int(demo.sim.fight.action_count).is_equal(3)
	assert_str(demo.overlay._header.text).contains("action 3")
	while not demo.sim.fight.is_over():
		demo.step()
	var finished: Fight = demo.sim.fight
	demo.step()
	assert_object(demo.sim.fight).is_not_same(finished)
	assert_object(demo.overlay.fight).is_same(demo.sim.fight)


func test_the_snapshot_shows_each_units_personality() -> void:
	var sim := _fight()
	var planner := IntentPlanner.new()
	var source := func(f: Fight, unit: Combatant) -> String: return DebugOverlay.unit_personality(planner, f, unit)
	var snap := DebugOverlay.snapshot(sim.fight, 5, Callable(), source)
	for i in sim.fight.combatants.size():
		var c := sim.fight.combatants[i]
		var u: Dictionary = snap.units[i]
		if c.side == Combatant.Side.ENEMY:
			assert_str(u.personality).is_equal(
				DebugOverlay.personality_text(planner.personality_of(c), planner.weights.lean_floor))
		else:
			assert_str(u.personality).is_not_empty()


func test_personality_text_names_the_larger_end_and_its_lean() -> void:
	var p := Personality.new(2, -0.6, 0.4)
	p.reactive = 3.0
	p.methodical = 1.0
	assert_str(DebugOverlay.personality_text(p, 1.0)).is_equal("agg .60 sup .40 [rea .50]")
	assert_str(DebugOverlay.personality_text(Personality.new(3), 1.0)).is_equal("bal .00 bal .00 bal .00")
