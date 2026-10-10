extends GdUnitTestSuite
## Switchboard and SwitchboardScreen: every decision in one place, saved to a
## user file.

const USER_FILE := "user://switchboard_test.json"
const LAYERS := ["contracts", "bot_data", "fight", "campaign", "ui", "tools"]


func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(USER_FILE))


func _board() -> Switchboard:
	return Switchboard.load_board(USER_FILE)


func test_lists_every_decision_of_the_build_plan() -> void:
	var board := _board()
	assert_array(board.errors).is_empty()
	var ids := board.decisions.map(func(d: Dictionary) -> String: return d.id)
	for id in ["d-wait", "d-wait-length", "d-elasticity", "d-personality-map", "hp-carryover", "draft-rule",
			"act-maps/act1", "act-maps/act2", "act-maps/act3", "energy-grid", "grid-cost-owner", "squad-size",
			"act-pacing", "auto-expansion", "tier-rule"]:
		assert_array(ids).contains([id])


func test_every_decision_is_well_formed() -> void:
	for d in _board().decisions:
		assert_array(LAYERS).override_failure_message(d.id).contains([d.layer])
		assert_array(Switchboard.APPLIES_TEXT.keys()).override_failure_message(d.id).contains([d.applies])
		assert_bool(Switchboard.has_option_in(d, d.default)).override_failure_message(d.id).is_true()
		assert_int(d.options.size()).override_failure_message(d.id).is_greater(1)
		for o: Dictionary in d.options:
			if o.id == d.default:
				assert_bool(o.built).override_failure_message("%s default must be built" % d.id).is_true()


func test_defaults_come_from_the_files_that_own_them() -> void:
	var board := _board()
	assert_str(board.draft_rule()).is_equal(BotTuning.load_default().draft_rule)
	var plan := ActPlan.load_file("res://data/tuning/acts.json")
	var expected := PackedStringArray()
	for act in plan.act_count():
		expected.append(plan.chosen_variant(act))
	assert_array(board.act_map_variants()).is_equal(expected)
	assert_int(board.decision("act-maps/act1").options.size()).is_equal(plan.variants(0).size())
	assert_array(BotTuning.DRAFT_RULES).contains_exactly_in_any_order(
		board.decision("draft-rule").options.map(func(o: Dictionary) -> String: return o.id))


func test_fight_decisions_agree_with_the_fight_reader() -> void:
	var board := _board()
	var v := FightVariants.defaults()
	for id: String in FightVariants.KNOWN:
		assert_str(board.option_of(id)).is_equal(v.option(id))


func test_choices_save_and_reload() -> void:
	var board := _board()
	assert_bool(board.choose("d-wait", "extra_energy")).is_true()
	assert_bool(board.choose("draft-rule", "damage_guarantee")).is_true()
	assert_bool(board.choose("act-maps/act1", "lake_washington_8")).is_true()
	assert_int(board.save()).is_equal(OK)
	var again := _board()
	assert_str(again.option_of("d-wait")).is_equal("extra_energy")
	assert_str(again.draft_rule()).is_equal("damage_guarantee")
	assert_str(again.act_map_variants()[0]).is_equal("lake_washington_8")
	assert_str(again.summary()).is_equal("d-wait=extra_energy · draft-rule=damage_guarantee · act-maps/act1=lake_washington_8")
	# The fight layer reads the same file.
	assert_str(FightVariants.load_active(USER_FILE).option("d-wait")).is_equal("extra_energy")


func test_choosing_the_default_forgets_the_choice() -> void:
	var board := _board()
	board.choose("d-wait", "extra_energy")
	board.choose("d-wait", "banked")
	assert_dict(board.choices).is_empty()
	assert_str(board.summary()).is_empty()


func test_unknown_choices_are_refused() -> void:
	var board := _board()
	assert_bool(board.choose("d-wait", "nonsense")).is_false()
	assert_bool(board.choose("nonsense", "banked")).is_false()


func test_reset_clears_every_choice() -> void:
	var board := _board()
	board.choose("d-elasticity", "resist_knockback")
	board.reset()
	assert_dict(board.choices).is_empty()


func test_unbuilt_options_are_marked() -> void:
	var board := _board()
	assert_bool(board.is_built("tier-rule", "skill_levels")).is_false()
	assert_bool(board.is_built("d-wait", "bonus_damage")).is_true()
	assert_bool(board.is_built("energy-grid", "shared_pool")).is_true()


func test_screen_shows_a_picker_per_decision_and_saves_picks() -> void:
	var screen: SwitchboardScreen = auto_free(SwitchboardScreen.new())
	screen.board = _board()
	add_child(screen)
	await get_tree().process_frame
	assert_int(screen.pickers.size()).is_equal(screen.board.decisions.size())
	var picker := screen.pickers["d-elasticity"]
	assert_str(picker.get_item_metadata(picker.selected)).is_equal("none")
	var changes := [0]
	screen.changed.connect(func() -> void: changes[0] += 1)
	assert_bool(screen.pick("d-elasticity", "energy_when_hit")).is_true()
	assert_str(picker.get_item_metadata(picker.selected)).is_equal("energy_when_hit")
	assert_int(changes[0]).is_equal(1)
	assert_str(screen.summary_label.text).contains("d-elasticity=energy_when_hit")
	assert_str(_board().option_of("d-elasticity")).is_equal("energy_when_hit")
	screen.reset_all()
	assert_str(_board().option_of("d-elasticity")).is_equal("none")


func test_screen_refuses_unbuilt_options() -> void:
	var screen: SwitchboardScreen = auto_free(SwitchboardScreen.new())
	screen.board = _board()
	add_child(screen)
	await get_tree().process_frame
	assert_bool(screen.pick("tier-rule", "skill_levels")).is_false()
	var picker := screen.pickers["tier-rule"]
	for i in picker.item_count:
		assert_bool(picker.is_item_disabled(i)).is_equal(not screen.board.is_built("tier-rule", picker.get_item_metadata(i)))


func test_variant_label_shows_only_non_defaults() -> void:
	var label: VariantLabel = auto_free(VariantLabel.new())
	var board := _board()
	label.show_board(board)
	assert_bool(label.visible).is_false()
	board.choose("hp-carryover", "carry")
	label.show_board(board)
	assert_bool(label.visible).is_true()
	assert_str(label.text).is_equal("Variants: hp-carryover=carry")
