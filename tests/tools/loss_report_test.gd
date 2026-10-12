extends GdUnitTestSuite
## LossReport and the careful autoplay (tools/check_losses.gd).


func test_reports_every_act_reached_per_policy_and_limit() -> void:
	var report := LossReport.run(2, 1, [CampaignAutoplay.POLICY_BLIND] as Array[String])
	assert_array(report.problems).is_empty()
	assert_int(report.cells.size()).is_equal(LossReport.LIMIT_OPTIONS.size())
	for cell in report.cells:
		assert_int(cell.acts[0].reached).is_equal(2)
		assert_int(cell.acts[0].limit).is_equal(3)
		assert_int(cell.acts[0].losses).is_between(0, cell.acts[0].fights)
	assert_str(report.format_text()).contains("mean losses")
	assert_str(report.format_markdown()).contains("| Policy |")


func test_the_same_seeds_give_the_same_report() -> void:
	var one: Array[String] = [CampaignAutoplay.POLICY_BLIND]
	var limit: Array[String] = [CampaignVariants.LOSSES_THREE_PER_ACT]
	var a := LossReport.run(2, 3, one, limit)
	var b := LossReport.run(2, 3, one, limit)
	assert_int(a.cells[0].acts[0].losses).is_equal(b.cells[0].acts[0].losses)
	assert_int(a.cells[0].acts[0].fights).is_equal(b.cells[0].acts[0].fights)


## The careful policy plays a whole campaign by the map's odds.
func test_careful_autoplay_records_per_act_numbers() -> void:
	var autoplay := CampaignAutoplay.new()
	autoplay.policy = CampaignAutoplay.POLICY_CAREFUL
	var r := autoplay.play(1)
	assert_array(r.problems).is_empty()
	assert_int(r.losses_per_act.size()).is_greater(0)
	assert_int(r.losses_per_act.size()).is_equal(r.fights_per_act.size())
	assert_int(r.limit_per_act[0]).is_equal(3)


func test_rejects_unknown_policies_and_options() -> void:
	assert_array(LossReport.run(1, 1, ["reckless"] as Array[String]).problems).is_not_empty()
	assert_array(LossReport.run(1, 1, [CampaignAutoplay.POLICY_BLIND] as Array[String], ["nope"] as Array[String]).problems).is_not_empty()
	assert_int(preload("res://tools/check_losses.gd").main(PackedStringArray(["--bogus", "1"]))).is_equal(1)
