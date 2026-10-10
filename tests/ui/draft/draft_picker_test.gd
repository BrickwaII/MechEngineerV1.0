extends GdUnitTestSuite
## DraftPicker, headless: the seeded draft and the squad picks.

const SEED := 11

var _tuning: BotTuning


func before() -> void:
	_tuning = BotTuning.load_default()


func _picker() -> DraftPicker:
	return DraftPicker.new(_tuning, SEED)


func test_the_draft_is_the_seeded_factory_draft_sized_from_data() -> void:
	var picker := _picker()
	var expected := BotFactory.new(_tuning).build_draft(SEED)
	assert_int(picker.bots().size()).is_equal(_tuning.draft_size)
	assert_int(picker.squad_size()).is_equal(_tuning.squad_size)
	for i in expected.size():
		assert_str(picker.bots()[i].id).is_equal(expected[i].id)
		assert_str(picker.bots()[i].display_name).is_equal(expected[i].display_name)


func test_the_same_seed_gives_the_same_draft() -> void:
	var a := _picker().bots().map(func(b: Bot) -> String: return b.display_name)
	var b := _picker().bots().map(func(b: Bot) -> String: return b.display_name)
	assert_array(a).is_equal(b)


func test_toggle_picks_and_drops() -> void:
	var picker := _picker()
	var id := picker.bots()[1].id
	assert_str(picker.toggle(id)).is_empty()
	assert_bool(picker.is_picked(id)).is_true()
	assert_str(picker.toggle(id)).is_empty()
	assert_bool(picker.is_picked(id)).is_false()
	assert_str(picker.toggle("nobody")).is_equal("no bot nobody in the draft")


func test_a_full_squad_refuses_more_picks_and_can_start() -> void:
	var picker := _picker()
	for i in _tuning.squad_size:
		assert_bool(picker.can_start()).is_false()
		assert_str(picker.toggle(picker.bots()[i].id)).is_empty()
	assert_bool(picker.can_start()).is_true()
	var extra := picker.bots()[_tuning.squad_size].id
	assert_str(picker.toggle(extra)).is_equal("the squad is full: drop a bot first")
	assert_bool(picker.is_picked(extra)).is_false()


func test_summaries_are_the_picks_in_pick_order() -> void:
	var picker := _picker()
	var order: Array[String] = []
	for i in [3, 0, 4].slice(0, _tuning.squad_size):
		order.append(picker.bots()[i].id)
		picker.toggle(picker.bots()[i].id)
	var summaries := picker.summaries()
	assert_array(summaries.map(func(s: SquadMemberSummary) -> String: return s.id)).is_equal(order)
	var bot := picker.squad.get_bot(order[0])
	assert_int(summaries[0].hp).is_equal(bot.hp)
	assert_int(summaries[0].max_hp).is_equal(bot.stats.hp)
	assert_int(summaries[0].stats.attack).is_equal(bot.stats.attack)
	assert_str(summaries[0].personality_tag).is_equal(bot.personality.get_tag())
