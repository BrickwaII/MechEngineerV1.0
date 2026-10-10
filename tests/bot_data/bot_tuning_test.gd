extends GdUnitTestSuite


func _json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _valid_dicts() -> Array[Dictionary]:
	return [_json(BotTuning.TUNING_PATH), _json(BotTuning.SKILLS_PATH)]


func test_the_shipped_tuning_is_valid() -> void:
	var tuning := BotTuning.load_default()
	assert_array(tuning.validation_errors()).is_empty()


func test_sizes_come_from_the_data_file() -> void:
	var raw := _json(BotTuning.TUNING_PATH)
	var tuning := BotTuning.load_default()
	assert_int(tuning.draft_size).is_equal(int(raw["draft_size"]))
	assert_int(tuning.squad_size).is_equal(int(raw["squad_size"]))
	assert_int(tuning.augment_slot_count).is_equal(int(raw["augment_slot_count"]))
	assert_int(tuning.stat_ranges["hp"].y).is_equal(int(raw["stat_ranges"]["hp"][1]))


func test_the_draft_holds_five_and_the_player_fields_three() -> void:
	var tuning := BotTuning.load_default()
	assert_int(tuning.draft_size).is_equal(5)
	assert_int(tuning.squad_size).is_equal(3)


func test_skills_load_from_the_catalog_file() -> void:
	var raw: Array = _json(BotTuning.SKILLS_PATH)["skills"]
	var tuning := BotTuning.load_default()
	assert_array(tuning.skills).has_size(raw.size())
	assert_str(tuning.skills[0].display_name).is_equal(raw[0]["name"])
	assert_int(tuning.skills[0].energy_cost).is_equal(int(raw[0]["energy_cost"]))


func test_a_missing_file_is_reported() -> void:
	var tuning := BotTuning.load_from("res://data/bot_data/missing.json", BotTuning.SKILLS_PATH)
	assert_bool(tuning.is_valid()).is_false()


func test_a_missing_key_is_reported() -> void:
	var dicts := _valid_dicts()
	dicts[0].erase("squad_size")
	assert_bool(BotTuning.from_dictionaries(dicts[0], dicts[1]).is_valid()).is_false()


func test_a_draft_smaller_than_the_squad_is_rejected() -> void:
	var dicts := _valid_dicts()
	dicts[0]["draft_size"] = 2
	assert_bool(BotTuning.from_dictionaries(dicts[0], dicts[1]).is_valid()).is_false()


func test_a_reversed_stat_range_is_rejected() -> void:
	var dicts := _valid_dicts()
	dicts[0]["stat_ranges"]["speed"] = [9, 3]
	assert_bool(BotTuning.from_dictionaries(dicts[0], dicts[1]).is_valid()).is_false()


func test_a_personality_range_beyond_one_is_rejected() -> void:
	var dicts := _valid_dicts()
	dicts[0]["personality_start_range"] = [-1.5, 0.5]
	assert_bool(BotTuning.from_dictionaries(dicts[0], dicts[1]).is_valid()).is_false()


func test_too_few_names_for_the_draft_is_rejected() -> void:
	var dicts := _valid_dicts()
	dicts[0]["names"] = ["Solo"]
	assert_bool(BotTuning.from_dictionaries(dicts[0], dicts[1]).is_valid()).is_false()


func test_an_invalid_skill_in_the_catalog_is_rejected() -> void:
	var dicts := _valid_dicts()
	dicts[1]["skills"][0]["energy_cost"] = -2
	assert_bool(BotTuning.from_dictionaries(dicts[0], dicts[1]).is_valid()).is_false()
