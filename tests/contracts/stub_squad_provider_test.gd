extends GdUnitTestSuite


func test_is_a_squad_provider() -> void:
	assert_object(StubSquadProvider.new()).is_instanceof(SquadProvider)


func test_returns_four_distinct_bots() -> void:
	var squad := StubSquadProvider.new().get_squad()
	assert_array(squad).has_size(4)
	var ids := squad.map(func(m: SquadMemberSummary) -> String: return m.id)
	assert_array(ids).contains_exactly_in_any_order(["stub_bolt", "stub_anvil", "stub_spark", "stub_cog"])


func test_every_bot_is_complete() -> void:
	for member in StubSquadProvider.new().get_squad():
		assert_str(member.display_name).is_not_empty()
		assert_str(member.personality_tag).is_not_empty()
		assert_int(member.max_hp).is_greater(0)
		assert_int(member.hp).is_between(1, member.max_hp)
		assert_int(member.stats.hp).is_equal(member.max_hp)
		assert_array(member.skills).is_not_empty()
		for skill in member.skills:
			assert_str(skill[SquadMemberSummary.SKILL_NAME]).is_not_empty()
			assert_str(skill[SquadMemberSummary.SKILL_EFFECT_ID]).is_not_empty()
			assert_int(skill[SquadMemberSummary.SKILL_LEVEL]).is_greater_equal(1)


func test_changes_to_a_returned_squad_do_not_leak_into_the_next_call() -> void:
	var provider := StubSquadProvider.new()
	provider.get_squad()[0].hp = 0
	assert_int(provider.get_squad()[0].hp).is_greater(0)


func test_changes_to_a_returned_skill_do_not_leak_into_the_next_call() -> void:
	var provider := StubSquadProvider.new()
	provider.get_squad()[0].skills[0][SquadMemberSummary.SKILL_LEVEL] = 9
	assert_int(provider.get_squad()[0].skills[0][SquadMemberSummary.SKILL_LEVEL]).is_equal(1)
