extends GdUnitTestSuite
## FightCommandHandler, headless: whole fights driven by commands alone.

const SEED := 7


func _request(level := 1) -> FightRequest:
	return FightRequest.new(FightRequest.Kind.ATTACK, "test_territory", level, StubSquadProvider.new().get_squad())


func _handler(level := 1, auto := true) -> FightCommandHandler:
	return FightCommandHandler.new(Fight.new(_request(level), SEED), null, auto)


## The commands SimpleFightPolicy's choice would take: strongest affordable
## skill on the weakest opponent.
func _play_like_simple_policy(handler: FightCommandHandler) -> void:
	var fight := handler.fight
	var best := ""
	for id in handler.actor().skill_ids:
		if handler.skill_problem(id).is_empty() and (best.is_empty()
				or fight.tuning.skill(id).power_percent > fight.tuning.skill(best).power_percent):
			best = id
	var target: Combatant = null
	for c in fight.opponents_of(handler.actor()):
		if target == null or c.hp < target.hp:
			target = c
	assert_str(handler.apply(FightCommand.select_skill(best))).is_empty()
	assert_str(handler.apply(FightCommand.select_target(target.id))).is_empty()


func test_a_whole_fight_runs_on_commands_alone() -> void:
	var handler := _handler()
	var turns := 0
	while not handler.fight.is_over():
		assert_bool(handler.is_player_turn()).is_true()
		assert_str(handler.selected_bot_id).is_equal(handler.actor().id)
		_play_like_simple_policy(handler)
		turns += 1
	assert_int(turns).is_greater(0)
	assert_object(handler.actor()).is_null()
	assert_str(handler.apply(FightCommand.select_skill("strike"))).is_equal("the fight is over")


func test_commands_replay_the_headless_runner_exactly() -> void:
	var handler := _handler()
	while not handler.fight.is_over():
		_play_like_simple_policy(handler)
	var runner := HeadlessFightRunner.run(_request(), SEED, SimpleFightPolicy.new())
	assert_array(handler.fight.action_tags).is_equal(runner.action_tags)
	assert_int(handler.fight.result().outcome).is_equal(runner.result().outcome)
	assert_float(handler.fight.result().grid_cost).is_equal(runner.result().grid_cost)


func test_fight_over_is_emitted_once_with_the_result() -> void:
	var handler := _handler()
	var results: Array[FightResult] = []
	handler.fight_over.connect(func(r: FightResult) -> void: results.append(r))
	while not handler.fight.is_over():
		_play_like_simple_policy(handler)
	assert_int(results.size()).is_equal(1)
	assert_int(results[0].outcome).is_equal(handler.fight.outcome)


func test_action_resolved_reports_every_action() -> void:
	var handler := _handler()
	var tags: Array[String] = []
	handler.action_resolved.connect(func(_id: String, tag: String) -> void: tags.append(tag))
	var before := handler.fight.action_tags.size()
	_play_like_simple_policy(handler)
	assert_array(tags).is_equal(handler.fight.action_tags.slice(before))
	assert_bool(tags[0].begins_with(handler.fight.action_tags[before].get_slice(":", 0))).is_true()


func test_a_target_needs_a_skill_first() -> void:
	var handler := _handler()
	var enemy := handler.fight.living(Combatant.Side.ENEMY)[0]
	assert_str(handler.apply(FightCommand.select_target(enemy.id))).is_equal("choose a skill first")
	assert_int(handler.fight.action_count).is_equal(0)


func test_an_ally_is_not_a_target() -> void:
	var handler := _handler()
	handler.apply(FightCommand.select_skill("strike"))
	var problem := handler.apply(FightCommand.select_target(handler.actor().id))
	assert_str(problem).contains("may not target an ally")
	assert_str(handler.selected_skill_id).is_equal("strike")
	assert_int(handler.fight.action_count).is_equal(0)


func test_cancel_steps_the_selection_back() -> void:
	var handler := _handler()
	var actor_id := handler.actor().id
	assert_str(handler.apply(FightCommand.cancel())).is_equal("nothing to cancel")
	handler.apply(FightCommand.select_skill("strike"))
	assert_bool(handler.is_choosing_target()).is_true()
	assert_str(handler.apply(FightCommand.cancel())).is_empty()
	assert_bool(handler.is_choosing_target()).is_false()
	var other := _other_living_bot(handler)
	assert_str(handler.apply(FightCommand.select_bot(other.id))).is_empty()
	assert_str(handler.apply(FightCommand.cancel())).is_empty()
	assert_str(handler.selected_bot_id).is_equal(actor_id)


func test_a_bot_that_is_not_ready_can_be_looked_at_but_not_commanded() -> void:
	var handler := _handler()
	var other := _other_living_bot(handler)
	assert_str(handler.apply(FightCommand.select_bot(other.id))).is_empty()
	assert_str(handler.selected_bot_id).is_equal(other.id)
	assert_str(handler.apply(FightCommand.select_skill("strike"))).is_equal("%s is not ready to act" % other.display_name)
	assert_str(handler.apply(FightCommand.wait("strike"))).is_equal("%s is not ready to act" % other.display_name)


func test_enemies_are_not_selectable_as_bots() -> void:
	var handler := _handler()
	var enemy := handler.fight.living(Combatant.Side.ENEMY)[0]
	assert_str(handler.apply(FightCommand.select_bot(enemy.id))).is_equal("no bot %s" % enemy.id)
	assert_str(handler.apply(FightCommand.select_bot("nobody"))).is_equal("no bot nobody")


func test_an_unaffordable_skill_is_refused_and_can_be_waited_for() -> void:
	var tuning := CombatTuning.load_default()
	tuning.starting_energy_percent = 0
	tuning.recharge_milli_per_battery_per_tick = 0
	var handler := FightCommandHandler.new(Fight.new(_request(), SEED, tuning))
	var actor := handler.actor()
	var overload := handler.fight.tuning.skill("overload")
	assert_bool(actor.can_afford(overload)).is_false()
	assert_str(handler.apply(FightCommand.select_skill("overload"))).contains("needs 9 energy")
	assert_str(handler.apply(FightCommand.wait("overload"))).is_empty()
	assert_str(handler.fight.action_tags[0]).is_equal("%s:wait" % actor.id)
	assert_int(actor.wait_target_milli).is_equal(overload.energy_cost_milli())


func test_a_bare_wait_charges_for_the_cheapest_skill_out_of_reach() -> void:
	var tuning := CombatTuning.load_default()
	tuning.starting_energy_percent = 0
	tuning.recharge_milli_per_battery_per_tick = 0
	var handler := FightCommandHandler.new(Fight.new(_request(), SEED, tuning))
	var actor := handler.actor()
	assert_str(handler.default_wait_skill()).is_equal("heavy_strike")
	assert_str(handler.apply(FightCommand.wait())).is_empty()
	assert_int(actor.wait_target_milli).is_equal(tuning.skill("heavy_strike").energy_cost_milli())


func test_a_bare_wait_with_every_skill_ready_is_refused() -> void:
	var tuning := CombatTuning.load_default()
	tuning.starting_energy_percent = 100
	var handler := FightCommandHandler.new(Fight.new(_request(), SEED, tuning))
	assert_str(handler.default_wait_skill()).is_empty()
	assert_str(handler.apply(FightCommand.wait())).is_equal("nothing to wait for: every skill is ready")


func test_wait_uses_the_selected_skill() -> void:
	var handler := _handler()
	var actor_id := handler.actor().id
	handler.apply(FightCommand.select_skill("strike"))
	assert_str(handler.default_wait_skill()).is_equal("strike")
	assert_str(handler.apply(FightCommand.wait())).is_empty()
	assert_str(handler.fight.action_tags[0]).is_equal("%s:wait" % actor_id)


func test_enemy_turns_can_be_played_one_at_a_time() -> void:
	var handler := _handler(5, false)
	var guard := 0
	while not handler.is_enemy_turn() and not handler.fight.is_over() and guard < 50:
		_play_like_simple_policy(handler)
		guard += 1
	assert_bool(handler.is_enemy_turn()).is_true()
	assert_str(handler.apply(FightCommand.select_skill("strike"))).is_equal("not your turn")
	var count := handler.fight.action_count
	assert_bool(handler.resolve_enemy_turn()).is_true()
	assert_int(handler.fight.action_count).is_equal(count + 1)
	handler.resolve_enemy_turns()
	assert_bool(handler.is_enemy_turn()).is_false()
	assert_bool(handler.resolve_enemy_turn()).is_false()


func test_an_invalid_request_is_over_at_once() -> void:
	var empty: Array[SquadMemberSummary] = []
	var request := FightRequest.new(FightRequest.Kind.ATTACK, "t", 1, empty)
	var handler := FightCommandHandler.new(Fight.new(request, SEED))
	assert_bool(handler.fight.is_over()).is_true()
	assert_str(handler.apply(FightCommand.select_skill("strike"))).is_equal("the fight is over")
	assert_str(handler.apply(null)).is_equal("no command")


func test_commands_print_readably() -> void:
	assert_str(str(FightCommand.select_target("drone#1"))).is_equal("select_target drone#1")
	assert_str(str(FightCommand.cancel())).is_equal("cancel")


func _other_living_bot(handler: FightCommandHandler) -> Combatant:
	for c in handler.fight.living(Combatant.Side.PLAYER):
		if c.id != handler.actor().id:
			return c
	return null
