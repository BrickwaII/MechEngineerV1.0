extends GdUnitTestSuite

const DATA := {
	"time": {"points_per_day": 4, "label": "x"},
	"bands": [1, 2],
	"flat": 2.5,
}


func test_lookup_follows_a_dotted_path() -> void:
	var errors: Array[String] = []
	var r := DataReader.new(errors, "tuning")
	assert_int(r.lookup(DATA, "time.points_per_day")).is_equal(4)
	assert_float(r.lookup(DATA, "flat")).is_equal(2.5)
	assert_array(errors).is_empty()


func test_lookup_reports_a_missing_step_with_the_label() -> void:
	var errors: Array[String] = []
	var r := DataReader.new(errors, "acts")
	assert_object(r.lookup(DATA, "time.nope")).is_null()
	assert_object(r.lookup(DATA, "flat.deeper")).is_null()
	assert_array(errors).contains_exactly(["acts is missing 'time.nope'", "acts is missing 'flat.deeper'"])


func test_num_reads_numbers_and_reports_anything_else() -> void:
	var errors: Array[String] = []
	var r := DataReader.new(errors, "tuning")
	assert_float(r.num(DATA, "time.points_per_day")).is_equal(4.0)
	assert_float(r.num(DATA, "time.label")).is_equal(0.0)
	assert_float(r.num(DATA, "missing")).is_equal(0.0)
	assert_array(errors).contains_exactly(["tuning 'time.label' must be a number", "tuning is missing 'missing'"])


func test_list_reads_lists_and_reports_anything_else() -> void:
	var errors: Array[String] = []
	var r := DataReader.new(errors, "tuning")
	assert_array(r.list(DATA, "bands")).is_equal([1, 2])
	assert_array(r.list(DATA, "flat")).is_empty()
	assert_array(errors).contains_exactly(["tuning 'flat' must be a list"])


func test_non_empty_string() -> void:
	var errors: Array[String] = []
	assert_str(DataReader.non_empty_string({"id": "a"}, "id", "region 1", errors)).is_equal("a")
	assert_str(DataReader.non_empty_string({"id": ""}, "id", "region 2", errors)).is_empty()
	assert_str(DataReader.non_empty_string({"id": 3}, "id", "region 3", errors)).is_empty()
	assert_array(errors).contains_exactly(["region 2 needs a non-empty 'id'", "region 3 needs a non-empty 'id'"])


func test_number_or_falls_back_when_absent_and_reports_a_wrong_type() -> void:
	var errors: Array[String] = []
	assert_float(DataReader.number_or({"e": 2}, "e", 1.0, "start a", errors)).is_equal(2.0)
	assert_float(DataReader.number_or({}, "e", 1.0, "start a", errors)).is_equal(1.0)
	assert_float(DataReader.number_or({"e": "x"}, "e", 1.0, "start b", errors)).is_equal(1.0)
	assert_array(errors).contains_exactly(["start b e must be a number"])
