extends GdUnitTestSuite

const KNOWN := {"speed": ["slow", "fast"], "size": ["small", "big"]}
const DATA := {"decisions": [
	{"id": "speed", "layer": "a", "default": "slow", "options": [
		{"id": "slow"}, {"id": "fast", "params": {"factor": 2, "name": "quick"}}]},
	{"id": "size", "layer": "a", "default": "small", "options": [{"id": "small"}, {"id": "big"}]},
	{"id": "extra", "layer": "a", "default": "on", "options": [{"id": "on"}, {"id": "off"}]},
	{"id": "other", "layer": "b", "default": "x", "options": [{"id": "x"}]},
]}


func _make(known_only := false) -> VariantSet:
	var v := VariantSet.new()
	v.read_decisions(DATA, "a", KNOWN, known_only)
	return v


func test_reads_only_its_layer_with_defaults_chosen() -> void:
	var v := _make()
	assert_dict(v.choices).is_equal({"speed": "slow", "size": "small", "extra": "on"})
	assert_dict(v.defaults_by_decision).is_equal(v.choices)
	assert_array(v.errors).is_empty()


func test_known_only_skips_decisions_the_code_does_not_know() -> void:
	assert_dict(_make(true).choices).is_equal({"speed": "slow", "size": "small"})


func test_missing_and_broken_decisions_are_reported() -> void:
	var v := VariantSet.new()
	v.read_decisions({"decisions": [
		{"id": "speed", "layer": "a", "default": "medium", "options": [{"id": "slow"}]},
	]}, "a", KNOWN)
	assert_array(v.errors).contains_exactly([
		"speed: default 'medium' is not one of its options",
		"speed: option fast is missing from the switchboard",
		"decision size is missing from the switchboard",
		"size: option small is missing from the switchboard",
		"size: option big is missing from the switchboard",
	])
	assert_str(v.option("size")).is_equal("small")
	var bad := VariantSet.new()
	bad.read_decisions({"decisions": {}}, "a", {})
	assert_array(bad.errors).contains_exactly(["decisions must be a list"])


func test_choose_and_params() -> void:
	var v := _make()
	assert_bool(v.choose("speed", "fast")).is_true()
	assert_bool(v.choose("speed", "warp")).is_false()
	assert_bool(v.choose("nope", "fast")).is_false()
	assert_bool(v.is_chosen("speed", "fast")).is_true()
	assert_int(v.param_int("speed", "factor")).is_equal(2)
	assert_float(v.param_float("speed", "factor")).is_equal(2.0)
	assert_str(v.param_string("speed", "name")).is_equal("quick")
	assert_int(v.param_int("speed", "missing", 7)).is_equal(7)
	assert_str(v.option("nope")).is_empty()
	assert_dict(v.non_default()).is_equal({"speed": "fast"})


func test_choose_all_ignores_what_it_does_not_know() -> void:
	var v := _make()
	v.choose_all({"speed": "fast", "size": "huge", "nope": "x"})
	assert_dict(v.non_default()).is_equal({"speed": "fast"})
	v.choose_all("not a dictionary")
	assert_dict(v.non_default()).is_equal({"speed": "fast"})


func test_copy_is_independent() -> void:
	var v := _make()
	var copy := v.copy_into(VariantSet.new())
	copy.choose("speed", "fast")
	(copy.params_by_option.speed.fast as Dictionary)["factor"] = 3
	assert_str(v.option("speed")).is_equal("slow")
	assert_int(int(v.params_by_option.speed.fast.factor)).is_equal(2)
