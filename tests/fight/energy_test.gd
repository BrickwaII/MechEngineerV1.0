extends GdUnitTestSuite
const Legacy := preload("res://tests/fight/legacy_switches.gd")

const H := preload("res://tests/fight/fight_test_helpers.gd")

var _tuning: CombatTuning


func before_test() -> void:
	_tuning = CombatTuning.load_default()


func _unit(battery: int) -> Combatant:
	return Combatant.new("u", "U", Combatant.Side.PLAYER, 0, H.stats(10, 1, 0, 5, battery), 10, _tuning.player_skills, _tuning)


func test_pool_is_sized_by_battery_capacity() -> void:
	assert_int(_unit(10).max_energy_milli).is_equal(10 * Combatant.MILLI)
	assert_int(_unit(3).max_energy_milli).is_equal(3 * Combatant.MILLI)


func test_starts_at_the_tuned_share_of_the_pool() -> void:
	var u := _unit(10)
	assert_int(u.energy_milli).is_equal(10 * Combatant.MILLI * _tuning.starting_energy_percent / 100)


func test_recharges_every_tick_in_proportion_to_battery() -> void:
	var u := _unit(10)
	u.energy_milli = 0
	u.tick()
	assert_int(u.energy_milli).is_equal(10 * _tuning.recharge_milli_per_battery_per_tick)


func test_recharge_never_drops_below_the_floor() -> void:
	for battery in [0, 1, 2, 3]:
		var u := _unit(battery)
		assert_int(u.recharge_milli).is_greater_equal(_tuning.recharge_floor_milli_per_tick)
	var small := _unit(1)
	small.energy_milli = 0
	small.tick()
	assert_int(small.energy_milli).is_equal(_tuning.recharge_floor_milli_per_tick)


func test_recharge_stops_at_a_full_pool() -> void:
	var u := _unit(4)
	for i in 1000:
		u.tick()
	assert_int(u.energy_milli).is_equal(u.max_energy_milli)


func test_skill_use_drains_its_flat_cost() -> void:
	var fight := H.duel(H.stats(50, 10, 0, 20, 10), H.stats(50, 1, 0, 1, 10), _tuning)
	var ally := fight.advance()
	assert_str(ally.id).is_equal("ally")
	var heavy := _tuning.skill("heavy_strike")
	var before := ally.energy_milli
	assert_str(fight.submit(FightAction.use("heavy_strike", "foe#1"))).is_empty()
	assert_int(ally.energy_milli).is_equal(before - heavy.energy_cost_milli())
	assert_int(ally.energy_spent_milli).is_equal(heavy.energy_cost_milli())


func test_free_skill_costs_nothing() -> void:
	var fight := H.duel(H.stats(50, 10, 0, 20, 10), H.stats(50, 1, 0, 1, 10), _tuning)
	var ally := fight.advance()
	var before := ally.energy_milli
	fight.submit(FightAction.use("strike", "foe#1"))
	assert_int(ally.energy_milli).is_equal(before)


func test_cannot_use_a_skill_it_cannot_afford() -> void:
	var fight := H.duel(H.stats(50, 10, 0, 20, 10), H.stats(50, 1, 0, 1, 10), _tuning)
	var ally := fight.advance()
	ally.energy_milli = 0
	assert_str(fight.submit(FightAction.use("overload", "foe#1"))).contains("cannot afford")
	assert_int(ally.energy_milli).is_equal(0)


## These tests' numbers were worked out under the old fight switches.
func before() -> void:
	Legacy.pin()


func after() -> void:
	Legacy.unpin()

