extends GdUnitTestSuite
## ActMusic: one loop per act, crossfaded. Headless it plays nothing but keeps
## the same bookkeeping.

var settings: GameSettings
var music: ActMusic


func before_test() -> void:
	settings = GameSettings.new()
	music = auto_free(ActMusic.new())
	music.settings = settings
	music.audio_enabled = false


func test_each_act_has_its_own_track_and_later_acts_keep_the_last() -> void:
	var tracks := [ActMusic.track_for_act(0), ActMusic.track_for_act(1), ActMusic.track_for_act(2)]
	assert_array(tracks).contains_exactly(["act1_metro", "act2_continent", "act3_globe"])
	assert_str(ActMusic.track_for_act(7)).is_equal("act3_globe")
	for id: String in tracks:
		assert_bool(FeelData.audio()["music"].has(id)).is_true()
		assert_bool(ResourceLoader.exists(FeelData.audio()["music"][id]["file"])).is_true()


func test_the_first_track_starts_at_full_volume() -> void:
	music.play_act(0)
	assert_str(music.track).is_equal("act1_metro")
	assert_float(music.fade).is_equal(1.0)


func test_changing_act_crossfades_over_the_set_time() -> void:
	music.play_act(0)
	music.play_act(1)
	assert_str(music.track).is_equal("act2_continent")
	assert_float(music.fade).is_equal(0.0)
	var start := music.volumes_db()
	assert_float(start.x).is_equal(ScreenFeel.number("music.silent_db"))
	var crossfade := ScreenFeel.number("music.crossfade_ms") / 1000.0
	music.advance(crossfade / 2.0)
	assert_float(music.fade).is_equal_approx(0.5, 0.01)
	# Equal power: both are about 3 dB down halfway.
	var middle := music.volumes_db()
	assert_float(middle.x).is_less(0.0)
	assert_float(middle.y).is_greater(ScreenFeel.number("music.silent_db"))
	music.advance(crossfade)
	assert_float(music.fade).is_equal(1.0)


func test_playing_the_same_act_again_does_not_restart_it() -> void:
	music.play_act(1)
	music.play_act(1)
	assert_float(music.fade).is_equal(1.0)


func test_skipped_animations_cut_straight_to_the_new_track() -> void:
	settings.animation_speed = "skip"
	music.play_act(0)
	music.play_act(2)
	music.advance(0.0)
	assert_float(music.fade).is_equal(1.0)
