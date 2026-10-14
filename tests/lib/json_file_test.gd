extends GdUnitTestSuite

const DIR := "user://json_file_test"


func before_test() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	JsonFile.clear_cache()


func after_test() -> void:
	for file in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(file))
	DirAccess.remove_absolute(DIR)
	JsonFile.clear_cache()


func _file(name: String, text: String) -> String:
	var path := DIR.path_join(name)
	assert_int(JsonFile.write_text(path, text)).is_equal(OK)
	return path


func test_read_gives_any_json_value() -> void:
	assert_array(JsonFile.read(_file("list.json", "[1, 2]"))).is_equal([1.0, 2.0])
	assert_dict(JsonFile.read(_file("obj.json", "{\"a\": 1}"))).is_equal({"a": 1.0})


func test_read_object_is_null_unless_the_file_holds_an_object() -> void:
	assert_dict(JsonFile.read_object(_file("obj.json", "{\"a\": 1}"))).is_equal({"a": 1.0})
	assert_object(JsonFile.read_object(_file("list.json", "[1]"))).is_null()
	assert_object(JsonFile.read_object(_file("bad.json", "{nope"))).is_null()
	assert_object(JsonFile.read_object(DIR.path_join("missing.json"))).is_null()


func test_read_dict_is_empty_unless_the_file_holds_an_object() -> void:
	assert_dict(JsonFile.read_dict(_file("obj.json", "{\"a\": 1}"))).is_equal({"a": 1.0})
	assert_dict(JsonFile.read_dict(_file("list.json", "[1]"))).is_empty()
	assert_dict(JsonFile.read_dict(DIR.path_join("missing.json"))).is_empty()


func test_cached_read_happens_once_and_hands_out_copies() -> void:
	var path := _file("obj.json", "{\"a\": {\"b\": 1}}")
	var first: Dictionary = JsonFile.read_object_cached(path)
	first.a.b = 99
	_file("obj.json", "{\"a\": {\"b\": 2}}")
	# Neither the change to the copy nor the change on disk is seen.
	assert_dict(JsonFile.read_object_cached(path)).is_equal({"a": {"b": 1.0}})
	JsonFile.clear_cache()
	assert_dict(JsonFile.read_object_cached(path)).is_equal({"a": {"b": 2.0}})


func test_cached_read_of_a_bad_file_is_null_and_not_kept() -> void:
	var path := DIR.path_join("later.json")
	assert_object(JsonFile.read_object_cached(path)).is_null()
	_file("later.json", "{\"a\": 1}")
	assert_dict(JsonFile.read_object_cached(path)).is_equal({"a": 1.0})


func test_write_round_trips() -> void:
	var path := DIR.path_join("out.json")
	assert_int(JsonFile.write(path, {"b": 1, "a": [true, "x"]}, "\t")).is_equal(OK)
	assert_str(FileAccess.get_file_as_string(path)).is_equal(JSON.stringify({"b": 1, "a": [true, "x"]}, "\t"))
	assert_dict(JsonFile.read_object(path)).is_equal({"a": [true, "x"], "b": 1.0})


func test_write_to_a_missing_folder_fails() -> void:
	assert_int(JsonFile.write_text("user://json_file_test/no/such/dir/x.json", "{}")).is_not_equal(OK)
