extends GdUnitTestSuite
## Heal skills: restore hp to a living ally, never past max, never on an
## opponent, and replay exactly.

const H := preload("res://tests/fight/fight_test_helpers.gd")
const T := preload("res://tests/fight/intent/intent_test_helpers.gd")


## Medic (fast, acts first) and a hurt Grunt against Bolt.
func _fight(grunt_hp := 10) -> Fight:
	return T.fight(
		[{"id": "bolt", "stats": T.stats(60, 12, 4, 1, 10)}],
		[
			{"id": "medic#1", "stats": T.stats(30, 8, 2, 20, 10), "skills": ["strike", "repair"]},
			{"id": "grunt#1", "stats": T.stats(30, 6, 2, 4, 10), "skills": ["strike"], "hp": grunt_hp},
		])


func test_the_shipped_tuning_has_a_heal_skill() -> void:
	var tuning := CombatTuning.load_default()
	assert_bool(tuning.skill("repair").is_heal()).is_true()
	assert_bool(tuning.skill("strike").is_heal()).is_false()
	assert_array(tuning.validate()).is_empty()


func test_validate_reports_an_unknown_effect() -> void:
	var tuning := CombatTuning.load_default()
	tuning.skill("repair").effect = "teleport"
	assert_array(tuning.validate()).has_size(1)


func test_a_heal_restores_attack_times_power_to_an_ally() -> void:
	var f := _fight()
	assert_str(f.advance().id).is_equal("medic#1")
	assert_str(f.submit(FightAction.use("repair", "grunt#1"))).is_empty()
	assert_int(f.combatant("grunt#1").hp).is_equal(18)
	assert_str(f.log_text()).contains("Medic 1 uses Repair on Grunt 1: 8 healed, hp 10 -> 18")
	assert_array(f.action_tags).contains_exactly(["medic#1:repair"])


func test_a_heal_never_goes_past_max_hp() -> void:
	var f := _fight(27)
	f.advance()
	f.submit(FightAction.use("repair", "grunt#1"))
	assert_int(f.combatant("grunt#1").hp).is_equal(30)


func test_a_unit_may_heal_itself() -> void:
	var f := _fight()
	f.combatant("medic#1").hp = 5
	f.advance()
	assert_str(f.submit(FightAction.use("repair", "medic#1"))).is_empty()
	assert_int(f.combatant("medic#1").hp).is_equal(13)


func test_a_heal_spends_energy() -> void:
	var f := _fight()
	var medic := f.advance()
	var before := medic.energy_milli
	f.submit(FightAction.use("repair", "grunt#1"))
	assert_int(medic.energy_milli).is_equal(before - 2 * Combatant.MILLI)


func test_a_heal_may_not_target_an_opponent_and_an_attack_may_not_target_an_ally() -> void:
	var f := _fight()
	f.advance()
	assert_str(f.check_action(FightAction.use("repair", "bolt"))).contains("may not use repair on an opponent")
	assert_str(f.check_action(FightAction.use("strike", "grunt#1"))).contains("may not target an ally")


func test_a_heal_may_not_target_a_downed_ally() -> void:
	var f := _fight()
	f.combatant("grunt#1").hp = 0
	f.advance()
	assert_str(f.check_action(FightAction.use("repair", "grunt#1"))).contains("no living target")


func test_simple_and_random_policies_never_heal() -> void:
	var f := _fight()
	var medic := f.advance()
	var rng := RandomNumberGenerator.new()
	assert_str(SimpleFightPolicy.new().choose(f, medic, rng).skill_id).is_equal("strike")
	for i in 20:
		var action := RandomFightPolicy.new().choose(f, medic, rng)
		assert_str(action.skill_id).is_not_equal("repair")


func test_fights_with_a_healer_replay_exactly() -> void:
	var squad: Array[SquadMemberSummary] = [
		H.member("ace", H.stats(40, 9, 3, 6, 10)),
		H.member("bea", H.stats(40, 8, 4, 5, 12)),
	]
	var a := HeadlessFightRunner.run(H.request(squad, 5), 3, SimpleFightPolicy.new(), IntentFightPolicy.new())
	var b := HeadlessFightRunner.run(H.request(squad, 5), 3, SimpleFightPolicy.new(), IntentFightPolicy.new())
	assert_bool(a.is_over()).is_true()
	assert_str(a.log_text()).is_equal(b.log_text())
	assert_str(a.log_text()).not_contains("policy refused")
