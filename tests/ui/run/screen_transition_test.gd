extends GdUnitTestSuite
## ScreenTransition: the wipe between screens never blocks input and follows
## the animation speed setting.

var settings: GameSettings
var transition: ScreenTransition


func before_test() -> void:
	settings = GameSettings.new()
	transition = ScreenTransition.new()
	transition.settings = settings
	add_child(transition)
	await await_idle_frame()


func after_test() -> void:
	transition.free()


func test_a_wipe_covers_with_bands_that_ignore_the_mouse_then_clears() -> void:
	assert_bool(transition.cover()).is_true()
	assert_int(transition.bands.size()).is_equal(int(ScreenFeel.number("transition.bands")))
	for band in transition.bands:
		assert_int(band.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_bool(transition.is_playing()).is_true()
	await await_millis(int(ScreenFeel.number("transition.uncover_ms") * (1.0 + ScreenFeel.number("transition.band_stagger"))) + 150)
	assert_bool(transition.is_playing()).is_false()
	assert_array(transition.bands).is_empty()


func test_no_wipe_when_animations_are_skipped() -> void:
	settings.animation_speed = "skip"
	assert_bool(transition.cover()).is_false()
	assert_array(transition.bands).is_empty()


func test_finish_removes_a_wipe_in_flight() -> void:
	transition.cover()
	transition.finish()
	assert_array(transition.bands).is_empty()
	assert_bool(transition.is_playing()).is_false()
