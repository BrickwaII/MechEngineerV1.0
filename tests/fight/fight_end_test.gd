extends GdUnitTestSuite

const H := preload("res://tests/fight/fight_test_helpers.gd")


func _play(fight: Fight) -> Fight:
	var policy := SimpleFightPolicy.new()
	var actor := fight.advance()
	while actor != null:
		assert_str(fight.submit(policy.choose(fight, actor, null))).is_empty()
		actor = fight.advance()
	return fight


func test_victory_when_every_enemy_is_down() -> void:
	var fight := _play(H.duel(H.stats(80, 20, 5, 9, 10), H.stats(20, 2, 0, 3, 4)))
	assert_bool(fight.is_over()).is_true()
	assert_bool(fight.living(Combatant.Side.ENEMY).is_empty()).is_true()
	var result := fight.result()
	assert_object(result).is_instanceof(FightResult)
	assert_bool(result.is_victory()).is_true()
	assert_dict(result.rewards).is_equal({FightResult.ENERGY: 3, FightResult.MATERIAL: 1})


func test_defeat_when_every_ally_is_down() -> void:
	var fight := _play(H.duel(H.stats(20, 2, 0, 3, 4), H.stats(80, 20, 5, 9, 10)))
	assert_bool(fight.living(Combatant.Side.PLAYER).is_empty()).is_true()
	assert_bool(fight.result().is_victory()).is_false()
	assert_dict(fight.result().rewards).is_empty()


func test_grid_cost_grows_with_level_and_energy_spent() -> void:
	var fight := _play(H.duel(H.stats(80, 20, 5, 9, 10), H.stats(60, 2, 0, 3, 4)))
	var t := fight.tuning
	var spent := float(fight.energy_spent_milli(Combatant.Side.PLAYER)) / Combatant.MILLI
	assert_float(spent).is_greater(0.0)
	var expected := t.grid_base_cost + t.grid_cost_per_defense_level * fight.request.defense_level + t.grid_cost_per_energy_spent * spent
	assert_float(fight.result().grid_cost).is_equal_approx(expected, 0.0001)


func test_a_finished_fight_takes_no_more_turns() -> void:
	var fight := _play(H.duel(H.stats(80, 20, 5, 9, 10), H.stats(20, 2, 0, 3, 4)))
	assert_object(fight.advance()).is_null()
	assert_bool(fight.is_awaiting_decision()).is_false()
	assert_str(fight.submit(FightAction.use("strike", "foe#1"))).is_not_empty()


func test_every_decision_leaves_one_tag() -> void:
	var fight := _play(H.duel(H.stats(80, 20, 5, 9, 10), H.stats(60, 2, 0, 3, 4)))
	assert_int(fight.action_tags.size()).is_equal(fight.action_count)
	for tag in fight.action_tags:
		assert_bool(tag.begins_with("ally:") or tag.begins_with("foe#1:")).is_true()


func test_action_limit_ends_the_fight_in_defeat() -> void:
	var tuning := CombatTuning.load_default()
	tuning.max_actions = 3
	var fight := _play(H.duel(H.stats(999, 1, 0, 5, 4), H.stats(999, 1, 0, 5, 4), tuning))
	assert_int(fight.action_count).is_equal(3)
	assert_bool(fight.timed_out).is_true()
	assert_bool(fight.result().is_victory()).is_false()


func test_an_invalid_request_is_a_defeat_with_no_turns() -> void:
	var empty: Array[SquadMemberSummary] = []
	var fight := Fight.new(H.request(empty), 1)
	assert_bool(fight.is_over()).is_true()
	assert_object(fight.advance()).is_null()
	assert_bool(fight.result().is_victory()).is_false()


func test_squad_members_at_zero_hp_are_not_fielded() -> void:
	var squad: Array[SquadMemberSummary] = [
		H.member("up", H.stats(30, 5, 2, 5, 8)),
		H.member("down", H.stats(30, 5, 2, 5, 8), 0),
	]
	var fight := Fight.new(H.request(squad), 1)
	assert_int(fight.living(Combatant.Side.PLAYER).size()).is_equal(1)
	assert_object(fight.combatant("down")).is_null()


func test_squad_members_start_at_their_current_hp() -> void:
	var squad: Array[SquadMemberSummary] = [H.member("hurt", H.stats(30, 5, 2, 5, 8), 12)]
	var unit := Fight.new(H.request(squad), 1).combatant("hurt")
	assert_int(unit.hp).is_equal(12)
	assert_int(unit.max_hp).is_equal(30)
