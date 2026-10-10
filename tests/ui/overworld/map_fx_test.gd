extends GdUnitTestSuite
## MapFx, the map's moving parts, with no scene.

var settings: GameSettings
var fx: MapFx


func before_test() -> void:
	settings = GameSettings.new()
	fx = MapFx.new(settings)


func _ms(path: String) -> float:
	return ScreenFeel.number(path) / 1000.0


func test_a_hovered_region_lights_up_then_fades_when_left() -> void:
	fx.set_hovered("a")
	assert_bool(fx.is_animating()).is_true()
	fx.advance(_ms("map.hover_ms") / 2.0)
	assert_float(fx.hover_amount("a")).is_equal_approx(0.5, 0.01)
	fx.advance(_ms("map.hover_ms"))
	assert_float(fx.hover_amount("a")).is_equal(1.0)
	assert_bool(fx.is_animating()).is_false()
	fx.set_hovered("b")
	fx.advance(_ms("map.hover_ms") * 2.0)
	assert_float(fx.hover_amount("a")).is_equal(0.0)
	assert_float(fx.hover_amount("b")).is_equal(1.0)


func test_the_selection_pops_then_settles() -> void:
	assert_float(fx.select_pop_px()).is_equal(0.0)
	fx.selected()
	assert_float(fx.select_pop_px()).is_equal(ScreenFeel.number("map.select_pop_px"))
	fx.advance(_ms("map.select_ms"))
	assert_float(fx.select_pop_px()).is_equal(0.0)


func test_a_capture_sweeps_from_0_to_1_and_ends() -> void:
	fx.start_capture("a")
	assert_bool(fx.is_capturing("a")).is_true()
	assert_float(fx.capture_progress("a")).is_equal(0.0)
	assert_float(fx.capture_flash("a")).is_equal(1.0)
	fx.advance(_ms("map.capture_ms") / 2.0)
	assert_float(fx.capture_progress("a")).is_equal_approx(0.5, 0.01)
	assert_float(fx.capture_flash("a")).is_equal(0.0)
	fx.advance(_ms("map.capture_ms"))
	assert_bool(fx.is_capturing("a")).is_false()
	assert_float(fx.capture_progress("a")).is_equal(1.0)


func test_with_animations_skipped_a_capture_is_done_at_once() -> void:
	settings.animation_speed = "skip"
	fx.start_capture("a")
	assert_bool(fx.is_capturing("a")).is_false()


func test_animation_speed_shortens_the_capture() -> void:
	settings.animation_speed = "2x"
	fx.start_capture("a")
	fx.advance(_ms("map.capture_ms") / 2.0 + 0.001)
	assert_bool(fx.is_capturing("a")).is_false()


func test_a_ring_slides_to_a_new_pressure() -> void:
	assert_float(fx.ring_pressure("a", 20.0)).is_equal(20.0)
	assert_float(fx.ring_pressure("a", 60.0)).is_equal(20.0)
	fx.advance(_ms("map.ring_fill_ms") / 2.0)
	var middle := fx.ring_pressure("a", 60.0)
	assert_float(middle).is_greater(20.0)
	assert_float(middle).is_less(60.0)
	fx.advance(_ms("map.ring_fill_ms"))
	assert_float(fx.ring_pressure("a", 60.0)).is_equal(60.0)


func test_rings_pulse_from_the_warning_level_and_faster_when_imminent() -> void:
	var tuning := MapTuning.load_file("res://data/tuning/act1.json")
	assert_float(fx.ring_pulse_px(tuning.ring_warning_at - 1.0, tuning)).is_equal(0.0)
	var warning := []
	var imminent := []
	for i in 40:
		fx.advance(0.025)
		warning.append(fx.ring_pulse_px(tuning.ring_warning_at, tuning))
		imminent.append(fx.ring_pulse_px(tuning.imminent_at, tuning))
	assert_float(warning.max()).is_greater(0.0)
	assert_float(warning.max()).is_less_equal(ScreenFeel.number("map.ring_pulse_px"))
	assert_int(_peaks(imminent)).is_greater(_peaks(warning))


func test_reduced_motion_stops_the_pulses_and_the_pop() -> void:
	settings.reduced_motion = true
	var tuning := MapTuning.load_file("res://data/tuning/act1.json")
	fx.selected()
	fx.advance(0.3)
	assert_float(fx.ring_pulse_px(tuning.imminent_at, tuning)).is_equal(0.0)
	assert_float(fx.select_pop_px()).is_equal(0.0)
	assert_float(fx.pending_march_px()).is_equal(0.0)
	assert_float(fx.pending_pulse()).is_equal(1.0)


func test_the_pending_cost_marches_and_breathes() -> void:
	var start := fx.pending_march_px()
	fx.advance(0.5)
	assert_float(fx.pending_march_px()).is_greater(start)
	var levels := []
	for i in 20:
		fx.advance(0.05)
		levels.append(fx.pending_pulse())
	assert_float(levels.min()).is_less(levels.max())
	assert_float(levels.min()).is_greater_equal(1.0 - ScreenFeel.number("map.pending_pulse_alpha") - 1e-6)


func test_reset_forgets_the_old_map() -> void:
	fx.set_hovered("a")
	fx.start_capture("b")
	fx.ring_pressure("c", 10.0)
	fx.reset()
	assert_str(fx.hovered_id).is_empty()
	assert_bool(fx.is_capturing("b")).is_false()
	assert_float(fx.ring_pressure("c", 50.0)).is_equal(50.0)


static func _peaks(values: Array) -> int:
	var count := 0
	for i in range(1, values.size() - 1):
		if values[i] > values[i - 1] and values[i] >= values[i + 1]:
			count += 1
	return count
