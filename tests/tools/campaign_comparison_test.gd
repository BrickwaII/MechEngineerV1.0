extends GdUnitTestSuite
## CampaignAutoplay, CampaignComparison and compare_variants for campaign
## decisions. Each campaign plays three acts of real auto-fights, so runs are
## kept to one or two.


func test_every_campaign_decision_compares_every_option_default_first() -> void:
	for decision in CampaignComparison.comparable():
		var cmp := CampaignComparison.run(decision, 1, 1)
		assert_array(cmp.problems).override_failure_message(decision).is_empty()
		var options: Array = cmp.results.map(func(r: CampaignComparison.OptionResult) -> String: return r.option)
		assert_array(options).is_equal(CampaignVariants.KNOWN[decision])
		assert_bool(cmp.results[0].is_default).is_true()
		var text := cmp.format_text()
		for column in ["acts cleared", "days used", "fights", "forced def."]:
			assert_str(text).contains(column)


func test_an_unknown_decision_is_a_problem() -> void:
	assert_array(CampaignComparison.run("d-wait", 1, 1).problems).is_not_empty()


func test_a_campaign_plays_the_same_for_the_same_seed() -> void:
	var a := CampaignAutoplay.new().play(4)
	var b := CampaignAutoplay.new().play(4)
	assert_array(a.problems).is_empty()
	for key in ["acts_cleared", "days_used", "fights", "forced_defenses", "attacks_won", "end_grid", "actions"]:
		assert_that(b.get(key)).override_failure_message(key).is_equal(a.get(key))


func test_a_default_campaign_plays_to_its_end() -> void:
	var r := CampaignAutoplay.new().play(2)
	assert_array(r.problems).is_empty()
	assert_int(r.fights).is_greater(0)
	assert_int(r.days_used).is_greater(0)
	assert_bool(r.acts_cleared == 3 or r.acts_cleared < 3 and not r.boss_fought).is_true()


func test_auto_expansion_claims_ground_in_later_acts() -> void:
	var v := CampaignVariants.defaults()
	v.choose(CampaignVariants.AUTO_EXPANSION, CampaignVariants.EXPANSION_SIMPLE)
	# Reach the later acts even when the auto-player loses often.
	v.choose(CampaignVariants.LOSS_LIMIT, CampaignVariants.LOSSES_UNLIMITED)
	var claims := 0
	for run_seed in [1, 2, 3]:
		claims += CampaignAutoplay.new(v, v).play(run_seed).expansion_claims
	assert_int(claims).is_greater(0)


func test_squad_size_drafts_the_option_s_squad() -> void:
	var v := CampaignVariants.defaults()
	v.choose(CampaignVariants.SQUAD_SIZE, CampaignVariants.SQUAD_DRAFT6_FIELD4)
	var t := CampaignAutoplay.new(v, v).bot_tuning()
	assert_int(t.draft_size).is_equal(6)
	assert_int(t.squad_size).is_equal(4)


func test_the_command_line_takes_a_campaign_decision() -> void:
	assert_int(load("res://tools/compare_variants.gd").main(PackedStringArray(["--decision", "grid-cost-owner", "--runs", "1"]))).is_equal(0)
