extends GdUnitTestSuite
## BotSquad.to_fielded_squad(): a run keeps only the bots picked in the draft.


func test_dropping_the_bench_keeps_the_fielded_bots_in_field_order() -> void:
	var tuning := BotTuning.load_default()
	var draft := BotFactory.new(tuning).build_draft(7)
	var picks: Array[String] = [draft[3].id, draft[0].id, draft[4].id]
	var drafted := BotSquad.new(draft, picks, picks.size())
	var squad := drafted.to_fielded_squad()
	# The draft itself is left as it was; the bots are the same objects.
	assert_int(drafted.bots.size()).is_equal(draft.size())
	assert_object(squad.bots[0]).is_same(draft[3])
	assert_array(squad.bots.map(func(b: Bot) -> String: return b.id)).is_equal(Array(picks))
	assert_array(Array(squad.fielded_ids)).is_equal(Array(picks))
	assert_bool(squad.is_valid()).is_true()


func test_a_squad_with_no_bench_is_unchanged() -> void:
	var squad := BotFactory.new(BotTuning.load_default()).build_squad(7).to_fielded_squad().to_fielded_squad()
	assert_int(squad.bots.size()).is_equal(squad.squad_size)
	assert_bool(squad.is_valid()).is_true()
