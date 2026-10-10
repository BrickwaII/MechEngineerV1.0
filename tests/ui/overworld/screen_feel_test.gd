extends GdUnitTestSuite
## data/feel/screens.json keeps to the feel rules: UI responses in 100-250 ms,
## every sound and track it names exists.

## Interface responses: the player's hover, click and pick feedback.
const UI_RESPONSES := ["map.hover_ms", "map.select_ms", "map.meter_ms", "draft.flip_ms", "draft.lift_ms",
	"draft.snap_ms", "readout.bot_in_ms", "readout.row_in_ms", "transition.uncover_ms", "act_zoom.title_in_ms",
	"act_zoom.title_out_ms"]
const SOUNDS := ["map_select", "map_capture", "resource_gain", "resource_loss", "card_flip", "card_snap",
	"tally_tick", "level_up", "personality_shift", "screen_whoosh", "zoom_whoosh"]


func test_ui_responses_stay_within_100_to_250_ms() -> void:
	for path: String in UI_RESPONSES:
		assert_float(ScreenFeel.number(path, -1.0)).override_failure_message(path).is_between(100.0, 250.0)


func test_the_post_fight_payoffs_hold_longer_than_a_row() -> void:
	assert_float(ScreenFeel.number("readout.level_up_ms")).is_greater(ScreenFeel.number("readout.row_in_ms"))
	assert_float(ScreenFeel.number("readout.shift_ms")).is_greater(ScreenFeel.number("readout.row_in_ms"))


func test_seconds_follow_the_animation_speed() -> void:
	var settings := GameSettings.new()
	var base := ScreenFeel.number("map.capture_ms") / 1000.0
	assert_float(ScreenFeel.seconds("map.capture_ms", settings)).is_equal_approx(base, 1e-6)
	settings.animation_speed = "2x"
	assert_float(ScreenFeel.seconds("map.capture_ms", settings)).is_equal_approx(base / 2.0, 1e-6)
	settings.animation_speed = "skip"
	assert_float(ScreenFeel.seconds("map.capture_ms", settings)).is_equal(0.0)


func test_every_sound_is_known_and_repeats_are_throttled() -> void:
	for id: String in SOUNDS:
		var def := SoundPlayer.sound_def(id)
		assert_dict(def).override_failure_message(id).is_not_empty()
		assert_int(int(def["throttle"]["max"])).override_failure_message(id).is_less_equal(2)
		for file: String in def["files"]:
			assert_bool(ResourceLoader.exists(file)).override_failure_message(file).is_true()
