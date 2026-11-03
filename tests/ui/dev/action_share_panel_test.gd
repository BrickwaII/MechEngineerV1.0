extends GdUnitTestSuite
## The action-use panel (S9) shows FightSummary's counts, live, and never
## changes the fight.

const SANDBOX := "res://data/scenarios/sandbox_3v3.json"


func _sim(seed_value := 1) -> SimulatedFight:
	return ScenarioFiles.load_scenario(SANDBOX).resolve().start(seed_value)


func _state(fight: Fight) -> Array:
	return [FightLog.lines(fight.events), fight.timeline.current_tick, fight.action_count,
		fight.combatants.map(func(c: Combatant) -> Array: return [c.hp, c.gauge, c.energy_milli])]


func test_rows_are_the_summarys_uses_and_shares_most_used_first() -> void:
	var fight := _sim(2).run_to_end().fight
	var squad := FightSummary.of(fight).squad
	var rows := ActionSharePanel.share_rows(squad, 50)
	var total := 0
	for i in rows.size():
		var row: Dictionary = rows[i]
		assert_int(row.uses).is_equal(squad.action_uses[row.action])
		assert_int(row.percent).is_equal(squad.share_percent(row.action))
		assert_bool(row.over).is_equal(row.percent > 50)
		if i > 0:
			assert_int(row.uses).is_less_equal(rows[i - 1].uses)
		total += row.uses
	assert_int(rows.size()).is_equal(squad.action_uses.size())
	assert_int(total).is_equal(squad.decisions)


func test_shares_above_the_limit_are_marked() -> void:
	var t := FightSummary.Tally.new()
	t.decisions = 4
	t.action_uses = {"strike": 3, "brace": 1}
	var rows := ActionSharePanel.share_rows(t, 50)
	assert_that(rows).is_equal([
		{"action": "strike", "uses": 3, "percent": 75, "over": true},
		{"action": "brace", "uses": 1, "percent": 25, "over": false}])
	assert_str(ActionSharePanel.uses_text(t)).is_equal("strike 3 · brace 1")


func test_the_limit_is_the_harness_share_limit() -> void:
	var panel: ActionSharePanel = auto_free(ActionSharePanel.new())
	assert_int(panel.limit_percent).is_equal(HarnessSettings.load_default().max_action_share_percent)


func test_the_panel_follows_the_fight_and_never_changes_it() -> void:
	var sim := _sim(3)
	var panel: ActionSharePanel = auto_free(ActionSharePanel.new())
	add_child(panel)
	panel.fight = sim.fight
	assert_str(panel.bbcode()).contains("0 decisions")
	for i in 4:
		sim.step()
	sim.fight.advance()
	var before := _state(sim.fight)
	panel.refresh()
	assert_array(_state(sim.fight)).is_equal(before)
	var squad := FightSummary.of(sim.fight).squad
	assert_str(panel.bbcode()).contains("%d decisions" % squad.decisions)
	for action: String in squad.action_uses:
		assert_str(panel.bbcode()).contains(action)
	# Events raised by the fight mark the panel for a redraw.
	panel._dirty = false
	sim.step()
	assert_bool(panel._dirty).is_true()


func test_finished_fights_add_up_in_the_session_total() -> void:
	var panel: ActionSharePanel = auto_free(ActionSharePanel.new())
	add_child(panel)
	var expected := FightSummary.Tally.new()
	for seed_value in [1, 2, 3]:
		var fight := _sim(seed_value).run_to_end().fight
		panel.fight = fight
		expected.add(FightSummary.of(fight).squad)
	# The third is banked when the next fight (or none) replaces it.
	panel.fight = null
	assert_int(panel.session_fights).is_equal(3)
	assert_int(panel.session.decisions).is_equal(expected.decisions)
	assert_that(panel.session.action_uses).is_equal(expected.action_uses)
	assert_str(panel.bbcode()).contains("Session · 3 fights")
	panel.clear_session()
	assert_int(panel.session_fights).is_equal(0)


func test_an_unfinished_fight_is_not_banked() -> void:
	var panel: ActionSharePanel = auto_free(ActionSharePanel.new())
	add_child(panel)
	var sim := _sim(1)
	sim.step()
	panel.fight = sim.fight
	panel.fight = null
	assert_int(panel.session_fights).is_equal(0)


func test_the_enemy_side_can_be_shown() -> void:
	var fight := _sim(1).run_to_end().fight
	var panel: ActionSharePanel = auto_free(ActionSharePanel.new())
	add_child(panel)
	panel.side = Combatant.Side.ENEMY
	panel.fight = fight
	var enemies := FightSummary.of(fight).enemies
	assert_str(panel.bbcode()).contains("enemies · this fight · %d decisions" % enemies.decisions)
