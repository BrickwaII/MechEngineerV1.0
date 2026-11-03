extends GdUnitTestSuite
## GreedyFightPolicy (combat rework S8): the affordable action that takes the
## most HP off the opponents now, worked out on a FightCopy.

const A := preload("res://tests/fight/archetypes/archetype_test_helpers.gd")
const H := preload("res://tests/fight/fight_test_helpers.gd")


func _rng() -> RandomNumberGenerator:
	return RandomNumberGenerator.new()


## Every affordable damage action the pending unit could take now.
func _options(fight: Fight, actor: Combatant) -> Array[FightAction]:
	var out: Array[FightAction] = []
	for skill in actor.skills():
		if skill.is_damage() and skill.targets_opponents() and actor.can_afford(skill):
			for foe in fight.opponents_of(actor):
				out.append(FightAction.use(skill.id, foe.id))
	return out


func test_it_hits_the_target_it_hurts_most() -> void:
	var fight := A.fight({"rook": H.stats(40, 8, 4, 6, 10)}, {
		"hard": A.enemy("Hard", H.stats(40, 5, 12, 3, 6), ["strike"]),
		"soft": A.enemy("Soft", H.stats(40, 5, 0, 3, 6), ["strike"]),
	}, ["hard", "soft"] as Array[String])
	var actor := fight.advance()
	actor.energy_milli = actor.max_energy_milli
	var action := GreedyFightPolicy.new().choose(fight, actor, _rng())
	assert_str(fight.combatant(action.target_id).display_name).is_equal("Soft")


func test_its_choice_deals_at_least_as_much_as_every_other_option_each_turn() -> void:
	for make: Callable in [A.charger_fight, A.plated_fight, A.scaler_fight]:
		var fight: Fight = make.call()
		var greedy := GreedyFightPolicy.new()
		var enemy_policy := IntentFightPolicy.new(fight.planner())
		var actor := fight.advance()
		var checked := 0
		while actor != null:
			var policy: FightPolicy = greedy if actor.side == Combatant.Side.PLAYER else enemy_policy
			var action := policy.choose(fight, actor, _rng())
			if actor.side == Combatant.Side.PLAYER and action.kind == FightAction.Kind.SKILL:
				var dealt := GreedyFightPolicy.damage_of(fight, action)
				for other in _options(fight, actor):
					assert_int(dealt).is_greater_equal(GreedyFightPolicy.damage_of(fight, other))
				checked += 1
			assert_str(fight.submit(action)).is_empty()
			actor = fight.advance()
		assert_int(checked).is_greater(0)


func test_it_counts_the_payoff_on_an_exposed_enemy() -> void:
	# Same two foes; Exposed on one makes Heavy Strike there the most damage.
	var fight := A.fight({"rook": H.stats(40, 8, 4, 6, 10)}, {
		"foe": A.enemy("Foe", H.stats(80, 5, 2, 3, 6), ["strike"]),
	}, ["foe", "foe"] as Array[String])
	var actor := fight.advance()
	actor.energy_milli = actor.max_energy_milli
	var exposed := fight.combatant("foe#2")
	fight.statuses.apply(exposed, "exposed", actor.id, 0)
	var action := GreedyFightPolicy.new().choose(fight, actor, _rng())
	assert_str(action.skill_id).is_equal("heavy_strike")
	assert_str(action.target_id).is_equal(exposed.id)


func test_choosing_leaves_the_live_fight_untouched() -> void:
	var fight := A.plated_fight()
	var actor := fight.advance()
	var before := FightSummary.of(fight).to_dict()
	var energy := actor.energy_milli
	var events := fight.events.size()
	var log_size := fight.log_lines.size()
	GreedyFightPolicy.new().choose(fight, actor, _rng())
	assert_dict(FightSummary.of(fight).to_dict()).is_equal(before)
	assert_int(actor.energy_milli).is_equal(energy)
	assert_int(fight.events.size()).is_equal(events)
	assert_int(fight.log_lines.size()).is_equal(log_size)
	assert_object(fight.pending_actor).is_same(actor)


func test_it_waits_for_its_cheapest_attack_when_it_can_afford_none() -> void:
	var fight := A.plated_fight()
	var actor := fight.advance()
	actor.energy_milli = 0
	var action := GreedyFightPolicy.new().choose(fight, actor, _rng())
	assert_int(action.kind).is_equal(FightAction.Kind.WAIT)
	assert_str(action.skill_id).is_equal("strike")
	assert_str(fight.check_action(action)).is_empty()


func test_it_never_braces_and_replays() -> void:
	for make: Callable in [A.charger_fight, A.plated_fight, A.scaler_fight]:
		var a: Fight = A.play(make.call(), GreedyFightPolicy.new())
		var b: Fight = A.play(make.call(), GreedyFightPolicy.new())
		assert_bool(a.is_over()).is_true()
		assert_bool(a.log_text().contains("policy refused")).is_false()
		assert_bool(a.action_tags.any(func(t: String) -> bool: return t.ends_with(":brace") and not t.contains("#"))).is_false()
		assert_str(a.log_text()).is_equal(b.log_text())
