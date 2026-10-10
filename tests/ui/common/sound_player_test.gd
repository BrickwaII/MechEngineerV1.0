extends GdUnitTestSuite
## The sound player throttles repeats and varies pitch and sample.

var _now := 0


func _player() -> SoundPlayer:
	var player: SoundPlayer = auto_free(SoundPlayer.new())
	player.audio_enabled = false
	player.clock = func() -> int: return _now
	player.rng.seed = 11
	return player


func test_ten_quick_plays_of_one_sound_start_only_a_few() -> void:
	var player := _player()
	var started := 0
	for i in 10:
		_now = i * 5
		if player.play(&"hit_light"):
			started += 1
	var limit := int(SoundPlayer.sound_def(&"hit_light")["throttle"]["max"])
	assert_int(started).is_equal(limit)
	assert_int(started).is_less_equal(3)


func test_the_sound_plays_again_once_the_window_passes() -> void:
	var player := _player()
	var window := int(SoundPlayer.sound_def(&"hit_light")["throttle"]["window_ms"])
	for i in 5:
		player.play(&"hit_light")
	_now += window
	assert_bool(player.play(&"hit_light")).is_true()


func test_different_sounds_are_throttled_separately() -> void:
	var player := _player()
	for i in 5:
		player.play(&"hit_light")
	assert_bool(player.play(&"heal")).is_true()


func test_pitch_varies_within_the_set_range() -> void:
	var player := _player()
	var pitches := []
	player.sound_started.connect(func(_id: StringName, _file: String, pitch: float) -> void: pitches.append(pitch))
	var variation := float(SoundPlayer.sound_def(&"swing")["pitch_variation"])
	for i in 20:
		_now += 1000
		player.play(&"swing")
	assert_int(pitches.size()).is_equal(20)
	for pitch: float in pitches:
		assert_float(pitch).is_between(1.0 - variation, 1.0 + variation)
	assert_float(pitches.max() - pitches.min()).is_greater(0.0)


func test_a_sound_with_several_files_never_repeats_one_back_to_back() -> void:
	var player := _player()
	var files := []
	player.sound_started.connect(func(_id: StringName, file: String, _pitch: float) -> void: files.append(file))
	for i in 12:
		_now += 1000
		player.play(&"hit_light")
	for i in range(1, files.size()):
		assert_str(files[i]).is_not_equal(files[i - 1])


func test_unknown_sounds_do_not_play() -> void:
	assert_bool(_player().play(&"no_such_sound")).is_false()


func test_every_sound_file_exists_on_a_known_bus() -> void:
	var audio := FeelData.audio()
	var buses: Array = audio["buses"]
	for id: String in audio["sounds"]:
		var def := SoundPlayer.sound_def(id)
		assert_bool(def["bus"] in buses).override_failure_message(id).is_true()
		for file: String in def["files"]:
			assert_bool(ResourceLoader.exists(file)).override_failure_message(file).is_true()
	for id: String in audio["music"]:
		assert_bool(ResourceLoader.exists(audio["music"][id]["file"])).is_true()


func test_the_project_has_the_three_buses() -> void:
	for bus: String in FeelData.audio()["buses"]:
		assert_int(AudioServer.get_bus_index(bus)).override_failure_message(bus).is_greater(0)


func test_throttle_counts_starts_inside_the_window_only() -> void:
	var throttle := SoundThrottle.new()
	assert_bool(throttle.try_start(&"a", 0, 2, 100)).is_true()
	assert_bool(throttle.try_start(&"a", 10, 2, 100)).is_true()
	assert_bool(throttle.try_start(&"a", 20, 2, 100)).is_false()
	assert_bool(throttle.try_start(&"a", 100, 2, 100)).is_true()
