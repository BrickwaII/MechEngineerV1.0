extends GdUnitTestSuite


func test_records_are_appended_as_json_lines_and_read_back() -> void:
	var path := create_temp_dir("stats_log").path_join("sub/log.jsonl")
	assert_int(FightStatsLog.append(path, {"seed": 1, "outcome": "victory"})).is_equal(OK)
	assert_int(FightStatsLog.append_all(path, [{"seed": 2}, {"seed": 3}])).is_equal(OK)
	var lines := FileAccess.get_file_as_string(path).split("\n", false)
	assert_int(lines.size()).is_equal(3)
	assert_that(JSON.parse_string(lines[0])).is_equal({"seed": 1.0, "outcome": "victory"})
	assert_int(FightStatsLog.read_all(path).size()).is_equal(3)


func test_a_missing_log_reads_as_empty() -> void:
	assert_array(FightStatsLog.read_all(create_temp_dir("stats_log2").path_join("none.jsonl"))).is_empty()
