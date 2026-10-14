extends GdUnitTestSuite


func test_short_number_drops_the_decimal_of_whole_numbers() -> void:
	assert_str(TextFormat.short_number(10.0)).is_equal("10")
	assert_str(TextFormat.short_number(0.0)).is_equal("0")
	assert_str(TextFormat.short_number(-3.0)).is_equal("-3")
	assert_str(TextFormat.short_number(2.0000001)).is_equal("2")


func test_short_number_keeps_one_decimal_otherwise() -> void:
	assert_str(TextFormat.short_number(2.5)).is_equal("2.5")
	assert_str(TextFormat.short_number(1.25)).is_equal("1.2")
	assert_str(TextFormat.short_number(0.75)).is_equal("0.8")
