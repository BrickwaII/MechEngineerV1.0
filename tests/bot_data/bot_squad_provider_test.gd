extends GdUnitTestSuite

var _squad: BotSquad


func before_test() -> void:
	_squad = BotFactory.new(BotTuning.load_default()).build_squad(31)


func test_is_a_squad_provider() -> void:
	assert_object(BotSquadProvider.new(_squad)).is_instanceof(SquadProvider)


func test_returns_the_fielded_bots_in_order() -> void:
	var ids := BotSquadProvider.new(_squad).get_squad().map(func(m: SquadMemberSummary) -> String: return m.id)
	assert_array(ids).contains_exactly(_squad.fielded_ids)
	assert_array(ids).has_size(_squad.squad_size)


func test_every_bot_is_complete() -> void:
	for member in BotSquadProvider.new(_squad).get_squad():
		assert_str(member.display_name).is_not_empty()
		assert_str(member.personality_tag).is_not_empty()
		assert_int(member.max_hp).is_greater(0)
		assert_int(member.hp).is_between(1, member.max_hp)
		assert_int(member.stats.hp).is_equal(member.max_hp)


func test_summaries_match_the_bots() -> void:
	var member := BotSquadProvider.new(_squad).get_squad()[0]
	var bot := _squad.get_bot(member.id)
	assert_str(member.display_name).is_equal(bot.display_name)
	assert_str(member.personality_tag).is_equal(bot.personality.get_tag())
	assert_int(member.stats.speed).is_equal(bot.stats.speed)


func test_reflects_current_hp() -> void:
	var provider := BotSquadProvider.new(_squad)
	_squad.get_bot(_squad.fielded_ids[0]).hp = 4
	assert_int(provider.get_squad()[0].hp).is_equal(4)


func test_changes_to_a_returned_squad_do_not_leak_into_the_next_call() -> void:
	var provider := BotSquadProvider.new(_squad)
	provider.get_squad()[0].hp = 0
	provider.get_squad()[0].stats.attack = 99
	assert_int(provider.get_squad()[0].hp).is_greater(0)
	assert_int(provider.get_squad()[0].stats.attack).is_less(99)


func test_its_squad_makes_a_valid_fight_request() -> void:
	var request := FightRequest.new(FightRequest.Kind.ATTACK, "t1", 2, BotSquadProvider.new(_squad).get_squad())
	assert_bool(request.is_valid()).is_true()


func test_a_missing_squad_gives_an_empty_list() -> void:
	assert_array(BotSquadProvider.new(null).get_squad()).is_empty()
