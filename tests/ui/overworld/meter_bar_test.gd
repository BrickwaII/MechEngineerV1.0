extends GdUnitTestSuite
## The overworld's MeterBar: changes slide with a trailing ghost.

const MeterBar := preload("res://ui/overworld/meter_bar.gd")

var settings: GameSettings
var bar: Control


func before_test() -> void:
	settings = GameSettings.new()
	bar = auto_free(MeterBar.new())
	bar.settings = settings
	bar.animate_to(0.8, true)


func test_a_loss_drops_the_fill_and_the_trail_holds_then_drains() -> void:
	bar.animate_to(0.5)
	assert_float(bar.fill_ratio).is_equal_approx(0.5, 1e-6)
	assert_float(bar.trail_ratio).is_equal_approx(0.8, 1e-6)
	bar.advance(ScreenFeel.number("map.ghost_hold_ms") / 1000.0 * 0.9)
	assert_float(bar.trail_ratio).is_equal_approx(0.8, 1e-6)
	bar.advance(ScreenFeel.number("map.ghost_hold_ms") / 1000.0)
	bar.advance(ScreenFeel.number("map.ghost_drain_ms") / 1000.0 / 2.0)
	assert_float(bar.trail_ratio).is_less(0.8)
	assert_float(bar.trail_ratio).is_greater(0.5)
	bar.advance(1.0)
	assert_float(bar.trail_ratio).is_equal_approx(0.5, 1e-6)
	assert_bool(bar.is_animating()).is_false()


func test_a_gain_moves_the_trail_first_and_the_fill_grows_into_it() -> void:
	bar.animate_to(1.0)
	assert_float(bar.trail_ratio).is_equal_approx(1.0, 1e-6)
	assert_float(bar.fill_ratio).is_equal_approx(0.8, 1e-6)
	bar.advance(ScreenFeel.number("map.meter_ms") / 1000.0 / 2.0)
	assert_float(bar.fill_ratio).is_between(0.8, 1.0)
	bar.advance(1.0)
	assert_float(bar.fill_ratio).is_equal_approx(1.0, 1e-6)


func test_skipping_animations_jumps_the_bar() -> void:
	settings.animation_speed = "skip"
	bar.animate_to(0.2)
	assert_float(bar.fill_ratio).is_equal_approx(0.2, 1e-6)
	assert_float(bar.trail_ratio).is_equal_approx(0.2, 1e-6)
	assert_bool(bar.is_animating()).is_false()
