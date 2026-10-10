extends GdUnitTestSuite
## FightVariants: the fight layer's reader of the variant switchboard.

const USER_FILE := "user://fight_variants_test.json"


func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(USER_FILE))


func _write_user(choices: Dictionary) -> void:
	var f := FileAccess.open(USER_FILE, FileAccess.WRITE)
	f.store_string(JSON.stringify({"choices": choices}))
	f.close()


func test_defaults_are_todays_behaviour() -> void:
	var v := FightVariants.defaults()
	assert_array(v.errors).is_empty()
	assert_str(v.option(FightVariants.WAIT_FORM)).is_equal(FightVariants.WAIT_BANKED)
	assert_str(v.option(FightVariants.WAIT_LENGTH)).is_equal(FightVariants.WAIT_LENGTH_SNAP)
	assert_str(v.option(FightVariants.ELASTICITY)).is_equal(FightVariants.ELASTICITY_NONE)
	assert_str(v.option(FightVariants.PERSONALITY_MAP)).is_equal(FightVariants.PERSONALITY_CURRENT)
	assert_str(v.option(FightVariants.HP_CARRYOVER)).is_equal(FightVariants.HP_FULL_HEAL)
	assert_dict(v.non_default()).is_empty()


func test_reads_only_fight_decisions() -> void:
	var v := FightVariants.defaults()
	assert_array(v.choices.keys()).contains_exactly_in_any_order(FightVariants.KNOWN.keys())


func test_every_known_option_is_in_the_data_file() -> void:
	var v := FightVariants.defaults()
	for decision: String in FightVariants.KNOWN:
		for option: String in FightVariants.KNOWN[decision]:
			assert_bool(v.choose(decision, option)).override_failure_message("%s %s" % [decision, option]).is_true()


func test_choose_refuses_unknown_options() -> void:
	var v := FightVariants.defaults()
	assert_bool(v.choose(FightVariants.WAIT_FORM, "nonsense")).is_false()
	assert_bool(v.choose("no-such-decision", "x")).is_false()
	assert_str(v.option(FightVariants.WAIT_FORM)).is_equal(FightVariants.WAIT_BANKED)


func test_params_follow_the_chosen_option() -> void:
	var v := FightVariants.defaults()
	assert_int(v.param_int(FightVariants.WAIT_FORM, "extra_energy_points", -1)).is_equal(-1)
	v.choose(FightVariants.WAIT_FORM, FightVariants.WAIT_EXTRA_ENERGY)
	assert_int(v.param_int(FightVariants.WAIT_FORM, "extra_energy_points")).is_greater(0)


func test_load_active_applies_the_players_choices() -> void:
	_write_user({"d-wait": "bonus_damage", "d-elasticity": "energy_when_hit", "draft-rule": "damage_guarantee"})
	var v := FightVariants.load_active(USER_FILE)
	assert_str(v.option(FightVariants.WAIT_FORM)).is_equal(FightVariants.WAIT_BONUS_DAMAGE)
	assert_str(v.option(FightVariants.ELASTICITY)).is_equal(FightVariants.ELASTICITY_ENERGY)
	assert_dict(v.non_default()).is_equal({"d-wait": "bonus_damage", "d-elasticity": "energy_when_hit"})


func test_load_active_ignores_bad_choices_and_missing_files() -> void:
	_write_user({"d-wait": "nonsense"})
	assert_str(FightVariants.load_active(USER_FILE).option(FightVariants.WAIT_FORM)).is_equal(FightVariants.WAIT_BANKED)
	assert_dict(FightVariants.load_active("user://no_such_file.json").non_default()).is_empty()


func test_defaults_never_read_the_user_file() -> void:
	_write_user({"d-wait": "bonus_damage"})
	assert_str(FightVariants.defaults().option(FightVariants.WAIT_FORM)).is_equal(FightVariants.WAIT_BANKED)


func test_a_missing_decision_is_an_error_with_a_safe_default() -> void:
	var v := FightVariants.from_dict({"decisions": []})
	assert_array(v.errors).is_not_empty()
	assert_str(v.option(FightVariants.WAIT_FORM)).is_equal(FightVariants.WAIT_BANKED)


func test_combat_tuning_carries_default_variants() -> void:
	assert_dict(CombatTuning.load_default().variants.non_default()).is_empty()


func test_with_variants_copies_the_tuning() -> void:
	var base := CombatTuning.load_default()
	var v := FightVariants.defaults()
	v.choose(FightVariants.WAIT_FORM, FightVariants.WAIT_EXTRA_ENERGY)
	var t := base.with_variants(v)
	assert_object(t.variants).is_same(v)
	assert_int(t.action_threshold).is_equal(base.action_threshold)
	assert_array(t.skills.keys()).is_equal(base.skills.keys())
	assert_str(base.variants.option(FightVariants.WAIT_FORM)).is_equal(FightVariants.WAIT_BANKED)
