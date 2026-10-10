extends GdUnitTestSuite

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
