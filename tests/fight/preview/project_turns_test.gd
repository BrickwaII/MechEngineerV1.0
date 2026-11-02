extends GdUnitTestSuite
## Combat rework S2: FightPreview.project_turns() lists the next turns for a
## hypothetical action, and matches what actually happens when the fight is
## played by the policy the projection assumes.

const H := preload("res://tests/fight/fight_test_helpers.gd")

const LENGTH := 6


## The default tuning with recovery on the heavier attacks, so projections
## have something to get wrong.
func _tuning() -> CombatTuning:
	var t := CombatTuning.load_default()
	t.skills["heavy_strike"].recovery = 40
	t.skills["overload"].recovery = 80
	return t


func _fight(fight_seed: int) -> Fight:
	var table := H.table({"foe": H.enemy_def("Foe", H.stats(60, 6, 2, 6, 10), ["strike", "heavy_strike", "overload"])}, "foe", 2)
	var squad: Array[SquadMemberSummary] = [
		H.member("ace", H.stats(70, 7, 2, 9, 12)), H.member("rook", H.stats(90, 6, 3, 4, 10))]
	return Fight.new(H.request(squad), fight_seed, _tuning(), table)


## What HeadlessFightRunner.play_turn() would submit for `unit`.
func _choice(fight: Fight, unit: Combatant, rng: RandomNumberGenerator) -> FightAction:
	var action := IntentFightPolicy.new().choose(fight, unit, rng)
	if action == null or not fight.check_action(action).is_empty():
		action = SimpleFightPolicy.new().choose(fight, unit, rng)
	return action


static func _keys(entries: Array[TimelineEntry]) -> Array[String]:
	var out: Array[String] = []
	for e in entries:
		out.append("%s@%d%s" % [e.combatant_id, e.tick, "w" if e.ends_wait else ""])
	return out


func test_projection_matches_the_fight_played_out() -> void:
	var preview := FightPreview.new()
	for fight_seed in [1, 2, 3, 7]:
		var fight := _fight(fight_seed)
		var rng := HeadlessFightRunner.policy_rng(fight_seed)
		var turns: Array[String] = []
		var projected := {}
		var unit := fight.advance()
		while unit != null:
			var action := _choice(fight, unit, rng)
			var before := fight.log_lines.size()
			var projection := preview.project_turns(fight, action, LENGTH)
			# Projecting changes nothing in the fight.
			assert_int(fight.log_lines.size()).is_equal(before)
			projected[turns.size()] = _keys(projection)
			turns.append("%s@%d%s" % [unit.id, fight.timeline.current_tick, "w" if unit.is_waiting() else ""])
			assert_str(fight.submit(action)).is_empty()
			unit = fight.advance()
		assert_int(turns.size()).is_greater(LENGTH)
		for i: int in projected:
			var want := turns.slice(i + 1, i + 1 + LENGTH)
			assert_array(projected[i]).override_failure_message("seed %d, turn %d" % [fight_seed, i]).is_equal(want)


func test_a_heavy_action_projects_the_actor_later() -> void:
	var fight := _fight(1)
	var actor := fight.advance()
	var foe := fight.opponents_of(actor)[0].id
	actor.energy_milli = actor.max_energy_milli
	var preview := FightPreview.new()
	var next_turn := func(skill_id: String) -> int:
		for e in preview.project_turns(fight, FightAction.use(skill_id, foe), LENGTH):
			if e.combatant_id == actor.id:
				return e.tick
		return 1 << 30
	assert_int(next_turn.call("heavy_strike")).is_greater(next_turn.call("strike"))
	assert_int(next_turn.call("overload")).is_greater(next_turn.call("heavy_strike"))


func test_a_refused_action_projects_nothing() -> void:
	var fight := _fight(1)
	fight.advance()
	assert_array(FightPreview.new().project_turns(fight, FightAction.use("strike", "nobody"), LENGTH)).is_empty()


func test_projection_counts_a_delay_held_during_a_wait() -> void:
	# held_delay is copied into the projection's FightCopy.
	var fight := _fight(2)
	var actor := fight.advance()
	assert_str(fight.submit(FightAction.wait_for("overload"))).is_empty()
	TimelineOps.delay(fight, actor, TimelineOps.turn_gauge(60, fight.tuning))
	var unit := fight.advance()
	var rng := HeadlessFightRunner.policy_rng(2)
	var preview := FightPreview.new()
	var projection := _keys(preview.project_turns(fight, _choice(fight, unit, rng), LENGTH))
	var turns: Array[String] = []
	assert_str(fight.submit(_choice(fight, unit, rng))).is_empty()
	unit = fight.advance()
	while unit != null and turns.size() < LENGTH:
		turns.append("%s@%d%s" % [unit.id, fight.timeline.current_tick, "w" if unit.is_waiting() else ""])
		assert_str(fight.submit(_choice(fight, unit, rng))).is_empty()
		unit = fight.advance()
	assert_array(projection).is_equal(turns)
