extends GdUnitTestSuite


func test_options_lay_over_the_defaults() -> void:
	var opts := CliOptions.parse(PackedStringArray(["--runs", "5", "--set", "a=b"]), {"runs": "200", "seed": "1", "set": ""})
	assert_dict(opts).is_equal({"runs": "5", "seed": "1", "set": "a=b"})


func test_no_options_keep_the_defaults_and_leave_them_unchanged() -> void:
	var defaults := {"runs": "200"}
	var opts := CliOptions.parse(PackedStringArray(), defaults)
	opts.runs = "3"
	assert_dict(defaults).is_equal({"runs": "200"})


func test_an_unknown_or_incomplete_option_gives_nothing() -> void:
	assert_dict(CliOptions.parse(PackedStringArray(["--nope", "1"]), {"runs": "200"}, "Usage: x")).is_empty()
	assert_dict(CliOptions.parse(PackedStringArray(["--runs"]), {"runs": "200"})).is_empty()


func test_choices_are_parsed_and_trimmed() -> void:
	var into := {"old": "x"}
	assert_bool(CliOptions.parse_choices("speed-range = wide,strike-cost=free", into)).is_true()
	assert_dict(into).is_equal({"old": "x", "speed-range": "wide", "strike-cost": "free"})
	assert_bool(CliOptions.parse_choices("", into)).is_true()


func test_a_pair_without_equals_is_refused() -> void:
	var into := {}
	assert_bool(CliOptions.parse_choices("a=b,broken", into, "A switch set wants")).is_false()
