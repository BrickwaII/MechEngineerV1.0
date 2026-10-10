extends GdUnitTestSuite

const H := preload("res://tests/tools/tools_test_helpers.gd")


func _resolved(policy := "simple") -> ResolvedScenario:
	var r := H.scenario(policy).resolve(H.bot_tuning(), H.enemy_table(), H.combat_tuning())
	assert_array(r.problems).is_empty()
	return r


func test_it_plays_exactly_like_the_headless_runner() -> void:
	for policy in ["simple", "random"]:
		for seed_value in [1, 2, 3, 42]:
			var r := _resolved(policy)
			var sim := r.start(seed_value).run_to_end()
			var runner := HeadlessFightRunner.run(
				r.request, seed_value, FightScenario.make_policy(policy, []), SimpleFightPolicy.new(), r.tuning, r.enemy_table)
			assert_array(sim.fight.action_tags).is_equal(runner.action_tags)
			assert_str(sim.fight.log_text()).is_equal(runner.log_text())
			assert_int(sim.fight.outcome).is_equal(runner.outcome)


func test_the_damage_counted_is_the_hp_each_side_lost() -> void:
	var sim := _resolved("random").start(5).run_to_end()
	var dealt := {Combatant.Side.PLAYER: 0, Combatant.Side.ENEMY: 0}
	var lost := {Combatant.Side.PLAYER: 0, Combatant.Side.ENEMY: 0}
	for c in sim.fight.combatants:
		dealt[c.side] += sim.damage_dealt[c.id]
		lost[c.side] += c.max_hp - c.hp
	assert_int(dealt[Combatant.Side.PLAYER]).is_equal(lost[Combatant.Side.ENEMY])
	assert_int(dealt[Combatant.Side.ENEMY]).is_equal(lost[Combatant.Side.PLAYER])
	assert_int(dealt[Combatant.Side.PLAYER]).is_greater(0)


func test_step_plays_one_decision_at_a_time() -> void:
	var sim := _resolved().start(3)
	assert_int(sim.fight.action_count).is_equal(0)
	assert_bool(sim.step()).is_true()
	assert_int(sim.fight.action_count).is_equal(1)
	while sim.step():
		pass
	assert_bool(sim.fight.is_over()).is_true()
	assert_bool(sim.step()).is_false()


func test_a_record_holds_seed_outcome_length_and_per_unit_damage_and_energy() -> void:
	var sim := _resolved().start(9).run_to_end()
	var rec := sim.record("test duo")
	assert_str(rec.scenario).is_equal("test duo")
	assert_int(rec.seed).is_equal(9)
	assert_str(rec.outcome).is_equal("victory" if sim.fight.outcome == FightResult.Outcome.VICTORY else "defeat")
	assert_int(rec.actions).is_equal(sim.fight.action_count)
	assert_int(rec.ticks).is_equal(sim.fight.timeline.current_tick)
	assert_int(rec.units.size()).is_equal(sim.fight.combatants.size())
	var squad_energy := 0.0
	for u: Dictionary in rec.units:
		var c := sim.fight.combatant(u.id)
		assert_int(u.damage_dealt).is_equal(sim.damage_dealt[c.id])
		assert_float(u.energy_spent).is_equal(c.energy_spent_milli / 1000.0)
		if u.side == "player":
			squad_energy += u.energy_spent
	assert_float(rec.squad_energy_spent).is_equal(squad_energy)
	# A record is plain JSON data, so the log loses nothing (JSON reads numbers back as floats).
	var back: Dictionary = JSON.parse_string(JSON.stringify(rec))
	assert_array(back.keys()).contains_exactly_in_any_order(rec.keys())
	assert_float(back.seed).is_equal(9.0)
	assert_float(back.units[0].damage_dealt).is_equal(float(rec.units[0].damage_dealt))
