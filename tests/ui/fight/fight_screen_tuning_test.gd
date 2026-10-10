extends GdUnitTestSuite
## FightScreenTuning reads data/ui/fight_screen.json.


func test_the_data_file_loads_without_errors() -> void:
	var t := FightScreenTuning.load_default()
	assert_array(t.errors).is_empty()
	assert_int(t.timeline_length).is_greater(0)
	assert_float(t.enemy_turn_delay_seconds).is_greater_equal(0.0)
	assert_str(t.demo_territory_id).is_not_empty()


func test_missing_and_bad_values_are_reported() -> void:
	var t := FightScreenTuning.from_dict({"timeline_length": 0, "enemy_turn_delay_seconds": -1})
	assert_array(t.errors).contains([
		"timeline_length must be at least 1",
		"enemy_turn_delay_seconds may not be negative",
		"draft_seed is missing or not a number",
		"demo.territory_id is missing",
	])
	assert_array(FightScreenTuning.load_file("res://nope.json").errors).is_equal(["cannot read res://nope.json"])
