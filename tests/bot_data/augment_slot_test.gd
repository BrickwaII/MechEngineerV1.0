extends GdUnitTestSuite


func test_a_new_slot_is_empty() -> void:
	assert_bool(AugmentSlot.new().is_empty()).is_true()


func test_every_drafted_bot_has_the_tuned_slot_count() -> void:
	var tuning := BotTuning.load_default()
	assert_int(tuning.augment_slot_count).is_greater(0)
	for seed_value in [1, 2, 99]:
		for bot in BotFactory.new(tuning).build_draft(seed_value):
			assert_array(bot.augment_slots).has_size(tuning.augment_slot_count)


func test_drafted_slots_are_empty_and_distinct() -> void:
	var bots := BotFactory.new(BotTuning.load_default()).build_draft(5)
	for bot in bots:
		for slot in bot.augment_slots:
			assert_bool(slot.is_empty()).is_true()
	assert_object(bots[0].augment_slots[0]).is_not_same(bots[1].augment_slots[0])


func test_tuning_rejects_the_wrong_slot_count() -> void:
	var tuning := BotTuning.load_default()
	var bot := BotFactory.new(tuning).build_draft(5)[0]
	bot.augment_slots.append(AugmentSlot.new())
	assert_array(tuning.validation_errors_for(bot)).has_size(1)


func test_slots_hold_no_effects() -> void:
	var names: Array[String] = []
	for property in (AugmentSlot as Script).get_script_property_list():
		if property.usage & PROPERTY_USAGE_STORAGE:
			names.append(property.name)
	assert_array(names).contains_exactly(["augment_id"])
