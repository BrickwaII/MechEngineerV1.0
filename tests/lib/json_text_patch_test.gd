extends GdUnitTestSuite
## JsonTextPatch: one value changed in hand-written JSON, the rest kept.

const TEXT := "{\n\t\"_comment\": \"x\",\n\t\"actions\": {\n\t\t\"a\": {\"name\": \"A\", \"cost\": 1},\n\t\t\"b\": {\"name\": \"B\", \"cost\": 2, \"tags\": [\"x\", \"y\"]}\n\t}\n}\n"


func test_a_value_is_replaced_in_place() -> void:
	var r := JsonTextPatch.set_value(TEXT, ["actions", "a", "cost"], 5)
	assert_str(r.error).is_empty()
	assert_str(r.text).is_equal(TEXT.replace("\"cost\": 1", "\"cost\": 5"))


func test_a_missing_key_is_added_at_the_end_of_its_object() -> void:
	var r := JsonTextPatch.set_value(TEXT, ["actions", "a", "recovery"], 30)
	assert_str(r.error).is_empty()
	assert_str(r.text).contains("{\"name\": \"A\", \"cost\": 1, \"recovery\": 30}")
	assert_float(float(JsonTextPatch.get_value(r.text, ["actions", "a", "recovery"]))).is_equal(30.0)


func test_a_key_added_to_a_multi_line_object_gets_its_own_line() -> void:
	var r := JsonTextPatch.set_value(TEXT, ["extra"], 1)
	assert_str(r.error).is_empty()
	assert_str(r.text).contains("\t},\n\t\"extra\": 1\n}")


func test_values_after_arrays_and_strings_with_brackets_are_found() -> void:
	var text := "{\"s\": \"a}b,c\", \"l\": [1, {\"q\": 2}], \"n\": 3}"
	var r := JsonTextPatch.set_value(text, ["n"], 4)
	assert_str(r.text).is_equal("{\"s\": \"a}b,c\", \"l\": [1, {\"q\": 2}], \"n\": 4}")


func test_strings_floats_and_arrays_are_written_in_the_files_style() -> void:
	assert_str(JsonTextPatch.format("He said \"hi\"")).is_equal("\"He said \\\"hi\\\"\"")
	assert_str(JsonTextPatch.format(1.0)).is_equal("1.0")
	assert_str(JsonTextPatch.format(0.25)).is_equal("0.25")
	assert_str(JsonTextPatch.format(["a", 2])).is_equal("[\"a\", 2]")
	assert_str(JsonTextPatch.format({"k": true})).is_equal("{\"k\": true}")


func test_a_missing_middle_key_or_bad_text_is_refused_unchanged() -> void:
	var r := JsonTextPatch.set_value(TEXT, ["actions", "zzz", "cost"], 1)
	assert_str(r.error).is_not_empty()
	assert_str(r.text).is_equal(TEXT)
	assert_str(JsonTextPatch.set_value("{nope", ["a"], 1).error).is_not_empty()
	assert_str(JsonTextPatch.set_value(TEXT, ["_comment", "x"], 1).error).is_not_empty()


func test_every_shipped_action_field_can_be_set_and_reparsed() -> void:
	var text := FileAccess.get_file_as_string("res://data/combat/actions.json")
	var r := JsonTextPatch.set_value(text, ["actions", "heavy_strike", "recovery"], 60)
	assert_str(r.error).is_empty()
	var table := ActionTable.from_dict(JSON.parse_string(r.text))
	assert_int(table.actions["heavy_strike"].recovery).is_equal(60)
	assert_int(LineDiff.counts(text, r.text).removed).is_equal(1)
	assert_int(LineDiff.counts(text, r.text).added).is_equal(1)


func test_same_treats_json_numbers_alike() -> void:
	assert_bool(JsonTextPatch.same(4, 4.0)).is_true()
	assert_bool(JsonTextPatch.same([1, "a"], [1.0, "a"])).is_true()
	assert_bool(JsonTextPatch.same({"a": 1}, {"a": 2})).is_false()
