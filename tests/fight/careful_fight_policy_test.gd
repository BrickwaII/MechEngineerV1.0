extends GdUnitTestSuite
## CarefulFightPolicy: each rule it plays by, on the S5 archetype fights and
## small set-ups, against the greedy baseline (SimpleFightPolicy).

const A := preload("res://tests/fight/archetypes/archetype_test_helpers.gd")
const H := preload("res://tests/fight/fight_test_helpers.gd")


func _rng() -> RandomNumberGenerator:
	return RandomNumberGenerator.new()


func test_it_breaks_the_chargers_plating_and_loses_less_than_greedy() -> void:
	var careful := A.charger_fight()
	var events := A.record(careful)
	A.play(careful, CarefulFightPolicy.new())
	var greedy := A.play(A.charger_fight(), SimpleFightPolicy.new())
	assert_bool(A.won(careful)).is_true()
	assert_int(A.of_kind(events, FightEvent.Kind.STAGGER).size()).is_greater(0)
	assert_int(A.squad_hp_lost(careful)).is_less(A.squad_hp_lost(greedy))


func test_it_braces_against_a_wind_up_it_cannot_break() -> void:
	# No Shred: Brace is the only answer to the Charger's committed Ram.
	var t := A.tuning()
	t.player_skills.assign(["strike", "heavy_strike", "brace"])
	var fight := A.charger_fight(t)
	var events := A.record(fight)
	A.play(fight, CarefulFightPolicy.new())
	var braces := A.of_kind(events, FightEvent.Kind.BRACE)
	assert_int(braces.size()).is_greater(0)


func test_it_sets_up_shred_and_cashes_in_the_payoff() -> void:
	var fight := A.plated_fight()
	var events := A.record(fight)
	A.play(fight, CarefulFightPolicy.new())
	var payoffs := A.of_kind(events, FightEvent.Kind.HIT).filter(
		func(e: FightEvent) -> bool: return e.payoff_bonus_percent > 0 or e.status_bonus_percent > 0)
	assert_int(payoffs.size()).is_greater(0)
	assert_int(A.of_kind(events, FightEvent.Kind.STATUS_APPLIED).size()).is_greater(0)


func test_greedy_never_uses_the_setup() -> void:
	var fight := A.plated_fight()
	A.play(fight, SimpleFightPolicy.new())
	assert_bool(fight.action_tags.any(func(t: String) -> bool: return t.ends_with(":shred"))).is_false()


func test_it_heavy_strikes_an_exposed_enemy() -> void:
	var fight := A.fight(A.allies(), {"foe": A.enemy("Foe", H.stats(80, 5, 2, 3, 6), ["strike"])}, ["foe"] as Array[String])
	var actor := fight.advance()
	assert_object(actor).is_not_null()
	assert_int(actor.side).is_equal(Combatant.Side.PLAYER)
	var foe := fight.combatant("foe#1")
	fight.statuses.apply(foe, "exposed", actor.id, 0)
	actor.energy_milli = actor.max_energy_milli
	var action := CarefulFightPolicy.new().choose(fight, actor, _rng())
	assert_str(action.skill_id).is_equal("heavy_strike")
	assert_str(action.target_id).is_equal(foe.id)


func test_it_banks_for_heavy_strike_when_strike_barely_scratches() -> void:
	# A thick hide: Strike does the floor, Heavy Strike much more.
	var fight := A.fight({"rook": H.stats(40, 9, 4, 6, 10)},
		{"wall": A.enemy("Wall", H.stats(200, 3, 16, 3, 6), ["strike"])}, ["wall"] as Array[String])
	var actor := fight.advance()
	var wall := fight.combatant("wall#1")
	actor.energy_milli = actor.skill("strike").energy_cost_milli()
	var strike := CarefulFightPolicy.damage(fight, actor, wall, actor.skill("strike"))
	var heavy := CarefulFightPolicy.damage(fight, actor, wall, actor.skill("heavy_strike"))
	assert_int(strike * 2).override_failure_message("strike %d heavy %d" % [strike, heavy]).is_less(heavy)
	var action := CarefulFightPolicy.new().choose(fight, actor, _rng())
	assert_int(action.kind).is_equal(FightAction.Kind.WAIT)
	assert_str(action.skill_id).is_equal("heavy_strike")
	assert_str(fight.check_action(action)).is_empty()


func test_it_finishes_with_the_cheapest_killing_hit() -> void:
	var fight := A.fight(A.allies(), {"weak": A.enemy("Weak", H.stats(3, 5, 0, 3, 6), ["strike"])}, ["weak"] as Array[String])
	var actor := fight.advance()
	actor.energy_milli = actor.max_energy_milli
	var action := CarefulFightPolicy.new().choose(fight, actor, _rng())
	assert_str(action.skill_id).is_equal("strike")


func test_every_choice_is_legal_and_replays() -> void:
	for make: Callable in [A.charger_fight, A.plated_fight, A.scaler_fight]:
		var a: Fight = make.call()
		A.play(a, CarefulFightPolicy.new())
		var b: Fight = make.call()
		A.play(b, CarefulFightPolicy.new())
		assert_bool(a.is_over()).is_true()
		assert_bool(a.log_text().contains("policy refused")).is_false()
		assert_str(a.log_text()).is_equal(b.log_text())


func test_it_plays_a_squad_without_the_new_verbs() -> void:
	var fight := HeadlessFightRunner.run(H.request(H.without_skills([H.member("a", H.stats(40, 8, 4, 6, 10))]), 1),
		3, CarefulFightPolicy.new(), IntentFightPolicy.new())
	assert_bool(fight.is_over()).is_true()
	assert_bool(fight.log_text().contains("policy refused")).is_false()
