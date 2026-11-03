extends GdUnitTestSuite
## SmartFightPolicy (combat rework S8): the careful rules plus a Brace against
## any big telegraphed hit, and the greedy fallback by real damage.

const A := preload("res://tests/fight/archetypes/archetype_test_helpers.gd")
const H := preload("res://tests/fight/fight_test_helpers.gd")


func _rng() -> RandomNumberGenerator:
	return RandomNumberGenerator.new()


## Rook (fast, full energy) against one Brute that hits hard and acts before
## Rook's next turn. `brute_hp` sets whether one hit can down it.
func _brute_fight(brute_attack: int, brute_hp := 200) -> Fight:
	var fight := A.fight({"rook": H.stats(30, 8, 3, 6, 10)},
		{"brute": A.enemy("Brute", H.stats(brute_hp, brute_attack, 2, 5, 6), ["strike"])}, ["brute"] as Array[String])
	var actor := fight.advance()
	assert_str(actor.id).is_equal("rook")
	actor.energy_milli = actor.max_energy_milli
	return fight


func test_it_braces_against_a_big_telegraphed_hit() -> void:
	var fight := _brute_fight(16)
	var smart := SmartFightPolicy.new()
	assert_object(smart.big_threat(fight, fight.pending_actor)).is_not_null()
	var action := smart.choose(fight, fight.pending_actor, _rng())
	assert_str(action.skill_id).is_equal("brace")
	assert_str(fight.check_action(action)).is_empty()


func test_it_kills_the_threat_instead_when_one_hit_can() -> void:
	var fight := _brute_fight(16, 4)
	var action := SmartFightPolicy.new().choose(fight, fight.pending_actor, _rng())
	assert_int(action.kind).is_equal(FightAction.Kind.SKILL)
	assert_str(action.target_id).is_equal("brute#1")
	assert_str(action.skill_id).is_not_equal("brace")


func test_a_small_hit_is_not_a_threat() -> void:
	var fight := _brute_fight(3)
	var smart := SmartFightPolicy.new()
	assert_object(smart.big_threat(fight, fight.pending_actor)).is_null()
	assert_str(smart.choose(fight, fight.pending_actor, _rng()).skill_id).is_not_equal("brace")


func test_the_threshold_comes_from_its_tuning() -> void:
	var fight := _brute_fight(16)
	var never := SmartPolicyTuning.from_dict({"brace_hp_percent": 1000, "order_lookahead": 8})
	assert_object(SmartFightPolicy.new(never).big_threat(fight, fight.pending_actor)).is_null()


func test_it_does_not_brace_twice() -> void:
	var fight := _brute_fight(16)
	fight.pending_actor.brace_absorb = 5
	assert_str(SmartFightPolicy.new().choose(fight, fight.pending_actor, _rng()).skill_id).is_not_equal("brace")


func test_every_choice_is_legal_and_replays() -> void:
	for make: Callable in [A.charger_fight, A.plated_fight, A.scaler_fight]:
		var a: Fight = A.play(make.call(), SmartFightPolicy.new())
		var b: Fight = A.play(make.call(), SmartFightPolicy.new())
		assert_bool(a.is_over()).is_true()
		assert_bool(a.log_text().contains("policy refused")).is_false()
		assert_str(a.log_text()).is_equal(b.log_text())


func test_it_beats_greedy_on_the_charger() -> void:
	var smart := A.play(A.charger_fight(), SmartFightPolicy.new())
	var greedy := A.play(A.charger_fight(), GreedyFightPolicy.new())
	assert_bool(A.won(smart)).is_true()
	assert_int(A.squad_hp_lost(smart)).is_less(A.squad_hp_lost(greedy))


func test_the_shipped_tuning_is_valid() -> void:
	assert_array(SmartPolicyTuning.from_dict(JsonFile.read_object(SmartPolicyTuning.DEFAULT_PATH)).validate()).is_empty()
	assert_array(SmartPolicyTuning.from_dict({"brace_hp_percent": -1, "order_lookahead": 1}).validate()).has_size(2)
