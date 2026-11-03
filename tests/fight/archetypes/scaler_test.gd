extends GdUnitTestSuite
## The Scaler (combat rework S5): attack grows by a share of its base each
## time it acts. Killing it first beats greedy play, which goes after the
## weaker escorts while it snowballs.

const A := preload("res://tests/fight/archetypes/archetype_test_helpers.gd")
const H := preload("res://tests/fight/fight_test_helpers.gd")

const SCALER := "scaler#1"


## Plays until the Scaler waits for a decision, allies striking a Grunt.
static func _scaler_turn(fight: Fight) -> Combatant:
	for i in 20:
		var actor := fight.advance()
		if actor == null or actor.id == SCALER:
			return actor
		if actor.side == Combatant.Side.PLAYER:
			fight.submit(FightAction.use("strike", "grunt#1" if fight.combatant("grunt#1").is_alive() else "grunt#2"))
		else:
			fight.submit(IntentFightPolicy.new(fight.planner()).choose(fight, actor, null))
	return null


func test_each_action_adds_a_share_of_the_base_attack() -> void:
	var fight := A.scaler_fight()
	var scaler := _scaler_turn(fight)
	var base := scaler.stats
	assert_int(base.attack).is_equal(7)
	fight.submit(fight.planner().plan(fight, scaler).action)
	assert_int(scaler.growth).is_equal(1)
	assert_int(scaler.stats.attack).is_equal(8)  # 7 + 7 x 20% (rounded down)
	var grew := A.of_kind(fight.last_events, FightEvent.Kind.GROWTH)
	assert_int(grew.size()).is_equal(1)
	assert_str(grew[0].actor_id).is_equal(SCALER)
	assert_int(grew[0].amount).is_equal(1)
	assert_bool(fight.log_text().contains("Scaler grows (x1): attack 7 -> 8")).is_true()
	# Growth is on the base, not compounded; other stats stay.
	_scaler_turn(fight)
	fight.submit(fight.planner().plan(fight, scaler).action)
	assert_int(scaler.stats.attack).is_equal(9)  # 7 + 7 x 40%
	assert_int(scaler.stats.defense).is_equal(base.defense)
	assert_int(scaler.base_stats.attack).is_equal(7)
	# The stats were replaced, not changed in place.
	assert_int(base.attack).is_equal(7)


func test_growth_raises_its_damage() -> void:
	var fight := A.scaler_fight()
	var scaler := _scaler_turn(fight)
	var before := DamageRules.damage_to(scaler, fight.combatant("rook"), scaler.skill("strike"), fight.tuning)
	for i in 3:
		fight.submit(fight.planner().plan(fight, scaler).action)
		_scaler_turn(fight)
	var after := DamageRules.damage_to(scaler, fight.combatant("rook"), scaler.skill("strike"), fight.tuning)
	assert_int(after).is_greater(before)


func test_a_wait_grows_it_too_but_a_staggered_turn_does_not() -> void:
	var fight := A.scaler_fight()
	var scaler := _scaler_turn(fight)
	fight.submit(FightAction.wait_for("strike"))
	assert_int(scaler.growth).is_equal(1)
	scaler.max_plating = 1
	scaler.staggered = true
	var events := A.record(fight)
	_scaler_turn(fight)
	assert_bool(A.of_kind(events, FightEvent.Kind.RECOVER).size() > 0).is_true()
	assert_int(scaler.growth).is_equal(1)


func test_a_battery_or_speed_scaler_recomputes_charge_and_battery() -> void:
	var fight := A.scaler_fight()
	var scaler := fight.combatant(SCALER)
	scaler.archetype = EnemyArchetype.from_dict("fast_scaler", {
		"name": "Fast Scaler", "scaling_percent_per_action": {"speed": 100, "battery_capacity": 50}})
	var charge := scaler.charge_per_tick
	var battery := scaler.max_energy_milli
	ArchetypeRules.grow(fight, scaler)
	assert_int(scaler.stats.speed).is_equal(12)
	assert_int(scaler.charge_per_tick).is_greater(charge)
	assert_int(scaler.max_energy_milli).is_equal(battery * 3 / 2)


func test_killing_the_scaler_first_beats_greedy_play() -> void:
	var greedy := A.play(A.scaler_fight(), SimpleFightPolicy.new())
	var answer := A.play(A.scaler_fight(), A.AnswerPolicy.new())
	assert_bool(A.won(answer)).is_true()
	assert_int(A.squad_hp_lost(answer)).is_less(A.squad_hp_lost(greedy))
	# Greedy let it grow further.
	var grown := func(f: Fight) -> int:
		var count := 0
		for line in f.log_lines:
			if line.contains("Scaler grows"):
				count += 1
		return count
	assert_int(grown.call(answer)).is_less(grown.call(greedy))
