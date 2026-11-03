extends GdUnitTestSuite
const Legacy := preload("res://tests/fight/legacy_switches.gd")

const H := preload("res://tests/fight/fight_test_helpers.gd")

var _tuning: CombatTuning


func before_test() -> void:
	_tuning = CombatTuning.load_default()


func _unit(id: String, speed: int, order: int) -> Combatant:
	var s := H.stats(10, 1, 0, speed, 10)
	return Combatant.new(id, id, Combatant.Side.PLAYER, order, s, 10, _tuning.player_skills, _tuning)


func _timeline(speeds: Array) -> Timeline:
	var units: Array[Combatant] = []
	for i in speeds.size():
		units.append(_unit("u%d" % i, speeds[i], i))
	return Timeline.new(units, _tuning.action_threshold)


## Runs the real timeline for `count` actions, each unit acting plainly.
func _play(timeline: Timeline, count: int) -> Array[String]:
	var ids: Array[String] = []
	for i in count:
		var unit := timeline.advance_to_next_ready()
		ids.append(unit.id)
		unit.finish_action(timeline.threshold)
	return ids


func test_faster_unit_acts_first() -> void:
	var timeline := _timeline([4, 10])
	assert_str(timeline.advance_to_next_ready().id).is_equal("u1")


func test_faster_unit_acts_more_often_in_proportion_to_speed() -> void:
	var ids := _play(_timeline([5, 10]), 30)
	assert_int(ids.count("u1")).is_equal(20)
	assert_int(ids.count("u0")).is_equal(10)


func test_preview_lists_the_next_actions_in_order() -> void:
	var entries := _timeline([5, 10]).preview(6)
	var ids := entries.map(func(e: TimelineEntry) -> String: return e.combatant_id)
	assert_array(ids).contains_exactly(["u1", "u1", "u0", "u1", "u1", "u0"])
	var ticks := entries.map(func(e: TimelineEntry) -> int: return e.tick)
	assert_array(ticks).contains_exactly([10, 20, 20, 30, 40, 40])


func test_preview_matches_what_actually_happens() -> void:
	var timeline := _timeline([3, 7, 9, 5])
	var predicted := timeline.preview(25).map(func(e: TimelineEntry) -> String: return e.combatant_id)
	assert_array(_play(timeline, 25)).contains_exactly(predicted)


func test_preview_changes_nothing() -> void:
	var timeline := _timeline([3, 7])
	timeline.preview(50)
	assert_int(timeline.current_tick).is_equal(0)
	for u in timeline.units:
		assert_int(u.gauge).is_equal(0)


func test_same_gauge_and_speed_goes_by_roster_order() -> void:
	# u1 and u2 both reach 100 at tick 10 with the same speed.
	var timeline := _timeline([5, 10, 10])
	assert_array(_play(timeline, 2)).contains_exactly(["u1", "u2"])


func test_overflow_carries_over() -> void:
	var timeline := _timeline([30])
	var unit := timeline.advance_to_next_ready()
	assert_int(unit.gauge).is_equal(120)
	unit.finish_action(timeline.threshold)
	assert_int(unit.gauge).is_equal(20)


func test_down_units_never_act() -> void:
	var timeline := _timeline([10, 5])
	timeline.units[0].hp = 0
	assert_array(_play(timeline, 3)).contains_exactly(["u1", "u1", "u1"])
	assert_array(timeline.preview(3).map(func(e: TimelineEntry) -> String: return e.combatant_id)) \
		.contains_exactly(["u1", "u1", "u1"])


func test_speed_below_minimum_still_charges() -> void:
	var timeline := _timeline([0])
	assert_object(timeline.advance_to_next_ready()).is_not_null()
	assert_int(timeline.current_tick).is_equal(ceili(float(_tuning.action_threshold) / _tuning.min_charge_per_tick))


## These tests' numbers were worked out under the old fight switches.
func before() -> void:
	Legacy.pin()


func after() -> void:
	Legacy.unpin()



## A wound-up enemy holds its wait until an opponent has acted
## (telegraph_wait); the preview counts each previewed action toward it, so
## the committed hit shows on the order, at the tick the fight lands it.
func test_preview_shows_where_a_wound_up_hit_lands() -> void:
	const A := preload("res://tests/fight/archetypes/archetype_test_helpers.gd")
	var fight := A.charger_fight()
	var policy := IntentFightPolicy.new(fight.planner())
	var rng := HeadlessFightRunner.policy_rng(fight.fight_seed)
	var charger: Combatant = null
	for c in fight.combatants:
		if c.id.begins_with("charger"):
			charger = c
	var actor := fight.advance()
	var guard := 0
	while actor != null and charger.committed == null and guard < 40:
		HeadlessFightRunner.play_turn(fight, actor, policy, SimpleFightPolicy.new(), rng)
		actor = fight.advance()
		guard += 1
	assert_object(charger.committed).is_not_null()
	assert_int(charger.telegraph_wait).is_greater(0)
	var upcoming := fight.upcoming(8)
	var slot := upcoming.map(func(e: TimelineEntry) -> String: return e.combatant_id).find(charger.id)
	assert_int(slot).is_greater(0)
	assert_bool(upcoming[slot].ends_wait).is_true()
	# Played on by the same choices nothing else changes (no recovery among
	# the strikes before it), the Ram lands at that tick.
	var expected := upcoming[slot].tick
	while actor != null and actor != charger and guard < 80:
		HeadlessFightRunner.play_turn(fight, actor, policy, SimpleFightPolicy.new(), rng)
		actor = fight.advance()
		guard += 1
	assert_object(actor).is_same(charger)
	assert_int(fight.timeline.current_tick).is_equal(expected)
