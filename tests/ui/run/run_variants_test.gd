extends GdUnitTestSuite
## Variants in a run: F4 opens the switchboard over the game, the corner label
## lists non-default choices, and a new run plays the draft rule and act maps.

const SCENE := preload("res://ui/run/run_flow.tscn")
const Helpers := preload("res://tests/ui/fight/fight_ui_helpers.gd")
const USER_FILE := "user://run_variants_test.json"

const RunData := preload("res://tests/ui/run/run_data_helpers.gd")
const RUNS_ROOT := "user://test_runs/run_variants_test"
var _flow: RunFlow


func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(USER_FILE))
	CampaignVariants.user_path = ""
	RunData.remove_tree(RUNS_ROOT)


func _save(choices: Dictionary) -> void:
	var board := Switchboard.load_board(USER_FILE)
	for id: String in choices:
		assert_bool(board.choose(id, choices[id])).is_true()
	board.save()


func _open() -> void:
	_flow = SCENE.instantiate()
	_flow.run_seed = 13
	_flow.auto_fights = true
	_flow.variants_path = USER_FILE
	_flow.fight_screen_tuning = Helpers.fast_tuning()
	_flow.runs_root = RUNS_ROOT
	var runner := scene_runner(auto_free(_flow))
	await runner.simulate_frames(2)


func test_label_is_hidden_with_every_default() -> void:
	await _open()
	assert_bool(_flow.variant_label.visible).is_false()


func test_label_lists_the_non_default_choices() -> void:
	_save({"d-wait": "bonus_damage", "hp-carryover": "carry"})
	await _open()
	assert_bool(_flow.variant_label.visible).is_true()
	assert_str(_flow.variant_label.text).is_equal("Variants: d-wait=bonus_damage · hp-carryover=carry")


func test_f4_toggles_the_switchboard_and_changes_update_the_label() -> void:
	await _open()
	var key := InputEventKey.new()
	key.keycode = KEY_F4
	key.pressed = true
	_flow._input(key)
	assert_object(_flow.switchboard_screen).is_not_null()
	assert_bool(_flow.switchboard_screen.closable).is_true()
	_flow.switchboard_screen.pick("d-elasticity", "reduce_big_hits")
	assert_str(_flow.variant_label.text).contains("d-elasticity=reduce_big_hits")
	assert_str(FightVariants.load_active(USER_FILE).option("d-elasticity")).is_equal("reduce_big_hits")
	_flow._input(key)
	assert_object(_flow.switchboard_screen).is_null()


func test_a_new_run_drafts_with_the_switchboard_rule() -> void:
	_save({"draft-rule": "non_strike_damage"})
	await _open()
	assert_str(_flow.draft_screen.bot_tuning.draft_rule).is_equal("non_strike_damage")


func test_a_new_run_plays_the_switchboard_act_maps() -> void:
	_save({"act-maps/act1": "lake_washington_8"})
	await _open()
	assert_str(_flow.run_map_variants()[0]).is_equal("lake_washington_8")
	_flow.map_variants = PackedStringArray(["lake_washington_16"])
	assert_str(_flow.run_map_variants()[0]).is_equal("lake_washington_16")


func test_fights_read_the_variants_file() -> void:
	_save({"d-wait": "extra_energy"})
	await _open()
	_flow.start_map(BotFactory.new(BotTuning.load_default()).build_squad(13), SkillUseLedger.new())
	assert_str(_flow.fight_service.variants_source.call().option("d-wait")).is_equal("extra_energy")


func test_a_new_run_drafts_with_the_switchboard_squad_size() -> void:
	_save({"squad-size": "draft6_field4"})
	await _open()
	assert_int(_flow.draft_screen.bot_tuning.draft_size).is_equal(6)
	assert_int(_flow.draft_screen.bot_tuning.squad_size).is_equal(4)


func test_the_map_reads_the_campaign_choices_from_the_same_file() -> void:
	_save({"auto-expansion": "simple", "energy-grid": "shared_pool"})
	await _open()
	_flow.start_map(BotFactory.new(BotTuning.load_default()).build_squad(13), SkillUseLedger.new())
	var c: Campaign = _flow.overworld.campaign
	assert_str(c.state.variants["auto-expansion"]).is_equal("simple")
	assert_float(c.state.energy).is_equal(0.0)


func test_the_fight_service_charges_a_lost_attack_when_it_owns_the_cost() -> void:
	_save({"grid-cost-owner": "fight_service"})
	await _open()
	_flow.start_map(BotFactory.new(BotTuning.load_default()).build_squad(13), SkillUseLedger.new())
	var v: CampaignVariants = _flow.fight_service.campaign_variants_source.call()
	assert_str(v.option("grid-cost-owner")).is_equal("fight_service")


func test_selecting_a_region_makes_it_the_expansion_focus() -> void:
	await _open()
	_flow.start_map(BotFactory.new(BotTuning.load_default()).build_squad(13), SkillUseLedger.new())
	var c: Campaign = _flow.overworld.campaign
	var region_id: String = c.map.ids()[0]
	_flow.overworld.map_view.region_selected.emit(region_id)
	assert_str(c.state.focus_id).is_equal(region_id)


func test_leaving_the_run_stops_the_campaign_reading_its_file() -> void:
	await _open()
	assert_str(CampaignVariants.user_path).is_equal(USER_FILE)
	_flow.get_parent().remove_child(_flow)
	assert_str(CampaignVariants.user_path).is_empty()
