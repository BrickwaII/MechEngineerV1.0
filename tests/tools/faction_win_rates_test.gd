extends GdUnitTestSuite
## FactionWinRates, the seeded batch check behind tools/check_factions.gd.


func test_one_row_per_faction_and_act_after_the_generic_row() -> void:
	var levels: Array[int] = [0, 2]
	var rates := FactionWinRates.run(2, 1, levels)
	assert_array(rates.problems).is_empty()
	var factions := FactionTable.load_default()
	assert_int(rates.rows.size()).is_equal(1 + factions.factions.size() * factions.tier_by_act.size())
	assert_str(rates.rows[0].id).is_equal(FactionWinRates.GENERIC_ROW)
	for row in rates.rows:
		assert_int(row.wins.size()).is_equal(levels.size())
		for w in row.wins:
			assert_int(w).is_between(0, 2)
	assert_str(rates.rows[1].tiers[0]).is_equal(factions.tier_for(rates.rows[1].act, 0))


func test_same_seeds_give_the_same_table() -> void:
	var levels: Array[int] = [1]
	assert_str(FactionWinRates.run(2, 3, levels).format_text()) \
		.is_equal(FactionWinRates.run(2, 3, levels).format_text())
	assert_str(FactionWinRates.run(2, 3, levels).format_markdown()).contains("| generic |")
