extends GdUnitTestSuite
## The feel tables in data/feel/ load and follow the feel rules.


func test_every_table_loads() -> void:
	for table in [FeelData.palette(), FeelData.feel(), FeelData.audio(), FeelData.settings(), FeelData.manifest()]:
		assert_dict(table).is_not_empty()


func test_every_palette_entry_is_a_color() -> void:
	for key: String in FeelData.palette():
		if key.begins_with("_"):
			continue
		assert_bool(Color.html_is_valid(FeelData.palette()[key])).override_failure_message(key).is_true()


func test_ui_tweens_stay_within_100_to_250_ms() -> void:
	var tweens: Dictionary = FeelData.feel()["tweens"]
	for name: String in tweens:
		if tweens[name].get("kind", "") == "ui":
			assert_float(float(tweens[name]["ms"])).override_failure_message(name).is_between(100.0, 250.0)


func test_an_attack_takes_300_to_600_ms() -> void:
	var attack: Dictionary = FeelData.feel()["attack"]
	var total := 0.0
	for part: String in attack["parts"]:
		total += float(FeelTween.preset(part)["ms"])
	assert_float(total).is_between(300.0, 600.0)


func test_hit_pauses_stay_within_60_to_100_ms() -> void:
	assert_float(FeelData.number("hit_pause.light_ms")).is_between(60.0, 100.0)
	assert_float(FeelData.number("hit_pause.heavy_ms")).is_between(60.0, 100.0)


func test_tween_presets_name_known_curves() -> void:
	for name: String in FeelTween.names():
		var preset := FeelTween.preset(name)
		assert_bool(FeelTween.TRANSITIONS.has(preset["trans"])).override_failure_message(name).is_true()
		assert_bool(FeelTween.EASES.has(preset["ease"])).override_failure_message(name).is_true()


func test_unknown_colors_stand_out() -> void:
	assert_object(FeelData.color("no_such_color")).is_equal(Color.MAGENTA)
