extends GdUnitTestSuite
## LineDiff: the diff Save to data shows before it writes.


func test_same_texts_have_no_diff() -> void:
	assert_str(LineDiff.unified("a\nb", "a\nb")).is_empty()


func test_a_changed_line_reads_as_removed_then_added_with_context() -> void:
	var diff := LineDiff.unified("one\ntwo\nthree\nfour\nfive", "one\ntwo\nTHREE\nfour\nfive", "f.json")
	assert_str(diff).is_equal("--- f.json\n+++ f.json\n  two\n- three\n+ THREE\n  four")


func test_far_apart_changes_are_split_by_a_gap() -> void:
	var a := "1\n2\n3\n4\n5\n6\n7"
	var b := "x\n2\n3\n4\n5\n6\ny"
	assert_str(LineDiff.unified(a, b)).is_equal("- 1\n+ x\n  2\n...\n  6\n- 7\n+ y")


func test_ops_cover_both_texts() -> void:
	var ops := LineDiff.ops("a\nb\nc", "a\nc\nd")
	assert_array(ops).is_equal([[" ", "a"], ["-", "b"], [" ", "c"], ["+", "d"]])
	assert_dict(LineDiff.counts("a\nb\nc", "a\nc\nd")).is_equal({"removed": 1, "added": 1})
