extends GdUnitTestSuite
## CsvFile: quoting and appending under one header.

const PATH := "user://test_csv_file/out.csv"


func after_test() -> void:
	DirAccess.remove_absolute(PATH)


func test_cells_with_commas_quotes_or_newlines_are_quoted() -> void:
	assert_str(CsvFile.line(["a", 1, true])).is_equal("a,1,true")
	assert_str(CsvFile.line(["a,b", "say \"hi\"", "x\ny"])).is_equal("\"a,b\",\"say \"\"hi\"\"\",\"x\ny\"")


func test_header_is_written_once() -> void:
	assert_int(CsvFile.append(PATH, ["k", "v"], [["a", 1]])).is_equal(OK)
	assert_int(CsvFile.append(PATH, ["k", "v"], [["b", 2], ["c", 3]])).is_equal(OK)
	assert_str(FileAccess.get_file_as_string(PATH)).is_equal("k,v\na,1\nb,2\nc,3\n")
