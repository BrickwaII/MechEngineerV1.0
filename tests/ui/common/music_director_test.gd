extends GdUnitTestSuite
## MusicDirector: one track per context, crossfaded; the map keeps one loop
## per act; RunFlow stages drive it. Headless it plays nothing but keeps the
## same bookkeeping.

var settings: GameSettings
var music: MusicDirector


func before_test() -> void:
	settings = GameSettings.new()
	music = auto_free(MusicDirector.new())
	music.settings = settings
	music.audio_enabled = false


func _context_ms() -> float:
	return float(MusicDirector.config()["crossfade_ms"])


func test_every_context_names_a_track_that_exists() -> void:
	var tracks: Dictionary = FeelData.audio()["music"]
	for name: String in [MusicDirector.MENU, MusicDirector.BATTLE, MusicDirector.READOUT,
			MusicDirector.VICTORY, MusicDirector.DEFEAT]:
		var id := music.track_for(name)
		assert_str(id).is_not_empty()
		assert_bool(tracks.has(id)).is_true()
		assert_bool(ResourceLoader.exists(tracks[id]["file"])).is_true()
	music.boss_battle = true
	assert_str(music.track_for(MusicDirector.BATTLE)).is_equal("battle_boss_loop")
	assert_bool(ResourceLoader.exists(tracks["battle_boss_loop"]["file"])).is_true()


func test_each_act_has_its_own_map_loop_and_later_acts_keep_the_last() -> void:
	var tracks := [MusicDirector.track_for_act(0), MusicDirector.track_for_act(1), MusicDirector.track_for_act(2)]
	assert_array(tracks).contains_exactly(["act1_metro", "act2_continent", "act3_globe"])
	assert_str(MusicDirector.track_for_act(7)).is_equal("act3_globe")
	for id: String in tracks:
		assert_bool(ResourceLoader.exists(FeelData.audio()["music"][id]["file"])).is_true()


func test_run_stages_pick_their_contexts() -> void:
	var expected := {"DRAFT": "menu_loop", "MAP": "act1_metro", "FIGHT": "battle_loop", "POST_FIGHT": "readout_loop"}
	for stage: String in expected:
		music.show_stage(stage)
		assert_str(music.track).is_equal(expected[stage])
	music.show_stage("NOT_A_STAGE")
	assert_str(music.track).is_equal("readout_loop")


func test_every_run_flow_stage_has_a_context() -> void:
	for stage: String in RunFlow.Stage.keys():
		assert_bool(MusicDirector.config()["stages"].has(stage)).override_failure_message(stage).is_true()


func test_the_first_track_starts_at_full_volume() -> void:
	music.play_context(MusicDirector.MENU)
	assert_str(music.track).is_equal("menu_loop")
	assert_float(music.fade).is_equal(1.0)


func test_changing_context_crossfades_over_the_set_time() -> void:
	music.play_context(MusicDirector.MENU)
	music.play_map(0)
	assert_str(music.track).is_equal("act1_metro")
	assert_float(music.fade).is_equal(0.0)
	assert_float(music.volumes_db().x).is_equal(float(MusicDirector.config()["silent_db"]))
	music.advance(_context_ms() / 2000.0)
	assert_float(music.fade).is_equal_approx(0.5, 0.01)
	var middle := music.volumes_db()
	assert_float(middle.x).is_less(0.0)
	assert_float(middle.y).is_greater(float(MusicDirector.config()["silent_db"]))
	music.advance(_context_ms() / 1000.0)
	assert_float(music.fade).is_equal(1.0)


func test_an_act_change_on_the_map_uses_the_slower_act_crossfade() -> void:
	music.play_map(0)
	music.play_map(1)
	assert_str(music.track).is_equal("act2_continent")
	var act_s := ScreenFeel.number("music.crossfade_ms") / 1000.0
	music.advance(act_s / 2.0)
	assert_float(music.fade).is_equal_approx(0.5, 0.01)


func test_the_map_returns_to_the_act_it_left() -> void:
	music.play_map(2)
	music.show_stage("FIGHT")
	music.show_stage("POST_FIGHT")
	music.show_stage("MAP")
	assert_str(music.track).is_equal("act3_globe")


func test_the_same_context_again_does_not_restart_it() -> void:
	music.play_map(1)
	music.play_map(1)
	assert_float(music.fade).is_equal(1.0)


func test_the_boss_flag_picks_the_boss_loop_and_clears_after_the_battle() -> void:
	music.play_map(0)
	music.boss_battle = true
	music.show_stage("FIGHT")
	assert_str(music.track).is_equal("battle_boss_loop")
	music.show_stage("POST_FIGHT")
	assert_bool(music.boss_battle).is_false()
	music.show_stage("FIGHT")
	assert_str(music.track).is_equal("battle_loop")


func test_a_sting_cuts_in_fast_and_is_not_restarted() -> void:
	music.play_map(0)
	music.play_context(MusicDirector.DEFEAT)
	assert_str(music.track).is_equal("sting_defeat")
	music.advance(float(MusicDirector.config()["sting_fade_ms"]) / 1000.0)
	assert_float(music.fade).is_equal(1.0)
	music.play_context(MusicDirector.DEFEAT)
	assert_float(music.fade).is_equal(1.0)


func test_skipped_animations_cut_straight_to_the_new_track() -> void:
	settings.animation_speed = "skip"
	music.play_context(MusicDirector.MENU)
	music.play_context(MusicDirector.BATTLE)
	assert_float(music.fade).is_equal(1.0)


func test_music_plays_on_the_music_volume_bus() -> void:
	assert_str(MusicDirector.bus()).is_equal(GameSettings.VOLUME_BUSES["music_volume"])
	var live := MusicDirector.new()
	live.settings = settings
	live.audio_enabled = true
	live.play_context(MusicDirector.MENU)
	assert_int(live.players().size()).is_equal(2)
	for player in live.players():
		assert_str(player.bus).is_equal(MusicDirector.bus())
	live.stop()
	live.free()


func test_the_game_has_one_director() -> void:
	assert_object(MusicDirector.current).is_not_null()
	assert_object(MusicDirector.current.get_parent()).is_same(Presentation)
