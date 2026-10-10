extends GdUnitTestSuite
## TODO(decision: d-wait): these pin the default rules, bonus recharge while
## waiting and snapping to the first affordable tick.

const H := preload("res://tests/fight/fight_test_helpers.gd")

var _tuning: CombatTuning


func before_test() -> void:
	_tuning = CombatTuning.load_default()


## Ally (fast, battery 10) against a foe too slow to act during the test.
func _fight() -> Fight:
	return H.duel(H.stats(50, 5, 0, 50, 10), H.stats(50, 1, 0, 1, 10), _tuning)


## Ticks from the wait until the ally's next turn, when it waits for `skill_id`
## starting from `start_energy` points.
func _ticks_to_wait(skill_id: String, start_energy: int) -> int:
	var fight := _fight()
	var ally := fight.advance()
	ally.energy_milli = start_energy * Combatant.MILLI
	var t0 := fight.timeline.current_tick
	assert_str(fight.submit(FightAction.wait_for(skill_id))).is_empty()
	assert_object(fight.advance()).is_same(ally)
	return fight.timeline.current_tick - t0


func test_waiting_recharges_faster_than_normal() -> void:
	var u := Combatant.new("u", "U", Combatant.Side.PLAYER, 0, H.stats(10, 1, 0, 5, 10), 10, _tuning.player_skills, _tuning)
	assert_int(u.wait_recharge_milli).is_equal(u.recharge_milli * (100 + _tuning.wait_recharge_bonus_percent) / 100)
	assert_int(u.wait_recharge_milli).is_greater(u.recharge_milli)


func test_wait_snaps_to_the_first_tick_the_skill_is_affordable() -> void:
	# Overload costs 9; from 5 points the ally needs 4000 milli at the wait rate.
	var u := _fight().combatant("ally")
	var expected := ceili(4000.0 / u.wait_recharge_milli)
	assert_int(_ticks_to_wait("overload", 5)).is_equal(expected)
	var fight := _fight()
	var ally := fight.advance()
	ally.energy_milli = 5 * Combatant.MILLI
	fight.submit(FightAction.wait_for("overload"))
	fight.advance()
	assert_bool(ally.can_afford(_tuning.skill("overload"))).is_true()


func test_zero_bonus_gives_a_plain_wait() -> void:
	_tuning.wait_recharge_bonus_percent = 0
	var u := _fight().combatant("ally")
	assert_int(u.wait_recharge_milli).is_equal(u.recharge_milli)
	assert_int(_ticks_to_wait("overload", 5)).is_equal(ceili(4000.0 / u.recharge_milli))


func test_bonus_shortens_the_wait() -> void:
	var with_bonus := _ticks_to_wait("overload", 5)
	_tuning.wait_recharge_bonus_percent = 0
	assert_int(with_bonus).is_less(_ticks_to_wait("overload", 5))


func test_waiting_for_an_affordable_skill_lasts_one_tick() -> void:
	assert_int(_ticks_to_wait("strike", 5)).is_equal(1)


func test_waiting_holds_the_gauge() -> void:
	var fight := _fight()
	var ally := fight.advance()
	var gauge := ally.gauge
	ally.energy_milli = 0
	fight.submit(FightAction.wait_for("overload"))
	fight.advance()
	assert_int(ally.gauge).is_equal(gauge)


func test_cannot_wait_for_a_skill_beyond_the_pool() -> void:
	var fight := H.duel(H.stats(50, 5, 0, 50, 5), H.stats(50, 1, 0, 1, 10), _tuning)
	fight.advance()
	assert_str(fight.submit(FightAction.wait_for("overload"))).contains("never afford")


func test_wait_is_tagged_and_logged() -> void:
	var fight := _fight()
	fight.advance()
	fight.submit(FightAction.wait_for("overload"))
	assert_array(fight.action_tags).contains_exactly(["ally:wait"])
	assert_str(fight.log_text()).contains("waits for Overload")


func test_after_the_wait_the_unit_acts_normally() -> void:
	var fight := _fight()
	var ally := fight.advance()
	ally.energy_milli = 0
	fight.submit(FightAction.wait_for("heavy_strike"))
	fight.advance()
	assert_str(fight.submit(FightAction.use("heavy_strike", "foe#1"))).is_empty()
	assert_bool(ally.is_waiting()).is_false()


func test_preview_shows_when_a_waiting_unit_acts() -> void:
	var fight := _fight()
	var ally := fight.advance()
	ally.energy_milli = 5 * Combatant.MILLI
	fight.submit(FightAction.wait_for("overload"))
	var next: TimelineEntry = fight.upcoming(1)[0]
	assert_bool(next.ends_wait).is_true()
	fight.advance()
	assert_int(next.tick).is_equal(fight.timeline.current_tick)
