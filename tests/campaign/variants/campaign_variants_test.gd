extends GdUnitTestSuite
## CampaignVariants: the campaign layer's reading of the switchboard.

const USER_FILE := "user://campaign_variants_test.json"


func after_test() -> void:
	CampaignVariants.user_path = ""
	DirAccess.remove_absolute(ProjectSettings.globalize_path(USER_FILE))


func _write(choices: Dictionary) -> void:
	var file := FileAccess.open(USER_FILE, FileAccess.WRITE)
	file.store_string(JSON.stringify({"choices": choices}))
	file.close()


func test_the_shipped_file_lists_every_known_option_with_no_errors() -> void:
	var v := CampaignVariants.defaults()
	assert_array(v.errors).is_empty()
	for id: String in CampaignVariants.KNOWN:
		assert_str(v.option(id)).is_equal(CampaignVariants.KNOWN[id][0])


func test_every_campaign_option_is_built() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CampaignVariants.DEFAULT_PATH))
	for entry: Dictionary in data.decisions:
		if CampaignVariants.KNOWN.has(entry.id):
			for o: Dictionary in entry.options:
				assert_bool(o.get("built", true)).override_failure_message("%s/%s" % [entry.id, o.id]).is_true()


func test_defaults_ignore_the_players_file_until_a_path_is_set() -> void:
	_write({"auto-expansion": "simple"})
	assert_str(CampaignVariants.load_active().option(CampaignVariants.AUTO_EXPANSION)).is_equal("off")
	CampaignVariants.user_path = USER_FILE
	assert_str(CampaignVariants.load_active().option(CampaignVariants.AUTO_EXPANSION)).is_equal("simple")
	assert_str(CampaignVariants.load_active(USER_FILE).option(CampaignVariants.AUTO_EXPANSION)).is_equal("simple")


func test_unknown_choices_are_ignored() -> void:
	_write({"auto-expansion": "everything", "no-such-decision": "x"})
	var v := CampaignVariants.load_active(USER_FILE)
	assert_str(v.option(CampaignVariants.AUTO_EXPANSION)).is_equal("off")
	assert_dict(v.non_default()).is_empty()


func test_a_run_keeps_only_next_run_decisions() -> void:
	var v := CampaignVariants.defaults()
	v.choose(CampaignVariants.ENERGY_GRID, CampaignVariants.ENERGY_SHARED_POOL)
	v.choose(CampaignVariants.GRID_COST_OWNER, CampaignVariants.GRID_NO_SURCHARGE)
	var kept := v.run_choices()
	assert_bool(kept.has(CampaignVariants.GRID_COST_OWNER)).is_false()
	assert_str(kept[CampaignVariants.ENERGY_GRID]).is_equal(CampaignVariants.ENERGY_SHARED_POOL)
	var back := CampaignVariants.for_run({"energy-grid": "shared_pool", "grid-cost-owner": "no_surcharge"})
	assert_str(back.option(CampaignVariants.ENERGY_GRID)).is_equal(CampaignVariants.ENERGY_SHARED_POOL)
	assert_str(back.option(CampaignVariants.GRID_COST_OWNER)).is_equal(CampaignVariants.GRID_MAP_SURCHARGE)


func test_squad_sizes_keep_the_bot_tuning_by_default() -> void:
	var v := CampaignVariants.defaults()
	assert_dict(v.squad_sizes()).is_empty()
	v.choose(CampaignVariants.SQUAD_SIZE, CampaignVariants.SQUAD_DRAFT6_FIELD4)
	assert_dict(v.squad_sizes()).is_equal({"draft_size": 6, "squad_size": 4})
	v.choose(CampaignVariants.SQUAD_SIZE, CampaignVariants.SQUAD_DRAFT4_FIELD3)
	assert_dict(v.squad_sizes()).is_equal({"draft_size": 4, "squad_size": 3})


func test_every_squad_size_drafts_and_fields_its_bots() -> void:
	for option: String in CampaignVariants.KNOWN[CampaignVariants.SQUAD_SIZE]:
		var v := CampaignVariants.defaults()
		v.choose(CampaignVariants.SQUAD_SIZE, option)
		var tuning := BotTuning.load_default()
		var sizes := v.squad_sizes()
		if not sizes.is_empty():
			tuning.draft_size = sizes.draft_size
			tuning.squad_size = sizes.squad_size
		var squad := BotFactory.new(tuning).build_squad(3)
		assert_int(squad.bots.size()).is_equal(tuning.draft_size)
		assert_int(squad.get_fielded().size()).is_equal(tuning.squad_size)
		assert_bool(squad.is_valid()).is_true()
