extends GdUnitTestSuite
## Skill uses count toward skill levels, and leftover uses carry between fights.
const Legacy := preload("res://tests/fight/legacy_switches.gd")

const P := preload("res://tests/fight/post_fight/post_fight_test_helpers.gd")


func _skill(bot: Bot, name: String) -> Skill:
	for s in bot.skills:
		if s.display_name == name:
			return s
	return null


func _uses(values: Dictionary) -> Dictionary[String, int]:
	var out: Dictionary[String, int] = {}
	out.assign(values)
	return out


func test_count_uses_skips_waits_and_other_units() -> void:
	var fight := P.fight_for([P.bot("a", 10), P.bot("b", 5)])
	P.play(fight, P.sample_steps())
	assert_dict(SkillProgress.count_uses(fight.decision_tags, "a")).is_equal(_uses({"heavy_strike": 2, "strike": 1}))
	assert_dict(SkillProgress.count_uses(fight.decision_tags, "b")).is_equal(_uses({"overload": 1}))


func test_repeated_use_raises_the_level() -> void:
	var bot := P.bot("a", 10)
	var changes := SkillProgress.apply(bot, _uses({"strike": 7}), SkillUseLedger.new(), P.tuning())
	# 3 uses per level: 7 uses give 2 levels and bank 1.
	assert_int(_skill(bot, "Strike").level).is_equal(3)
	assert_int(changes[0].levels_gained()).is_equal(2)
	assert_int(changes[0].banked_after).is_equal(1)


func test_too_few_uses_bank_without_a_level() -> void:
	var bot := P.bot("a", 10)
	var ledger := SkillUseLedger.new()
	SkillProgress.apply(bot, _uses({"heavy_strike": 2}), ledger, P.tuning())
	assert_int(_skill(bot, "Overcharge Shot").level).is_equal(1)
	assert_int(ledger.get_banked("a", "Overcharge Shot")).is_equal(2)


func test_counts_persist_across_fights() -> void:
	var bot := P.bot("a", 10)
	var ledger := SkillUseLedger.new()
	SkillProgress.apply(bot, _uses({"heavy_strike": 2}), ledger, P.tuning())
	var changes := SkillProgress.apply(bot, _uses({"heavy_strike": 2}), ledger, P.tuning())
	assert_int(_skill(bot, "Overcharge Shot").level).is_equal(2)
	assert_int(changes[0].banked_before).is_equal(2)
	assert_int(ledger.get_banked("a", "Overcharge Shot")).is_equal(1)


func test_ledger_survives_a_save() -> void:
	var ledger := SkillUseLedger.new()
	ledger.set_banked("a", "Strike", 2)
	var path := "user://skill_use_ledger_test.tres"
	assert_int(ResourceSaver.save(ledger, path)).is_equal(OK)
	var loaded: SkillUseLedger = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_int(loaded.get_banked("a", "Strike")).is_equal(2)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_level_stops_at_the_max() -> void:
	var bot := P.bot("a", 10)
	_skill(bot, "Strike").level = 9
	SkillProgress.apply(bot, _uses({"strike": 30}), SkillUseLedger.new(), P.tuning())
	assert_int(_skill(bot, "Strike").level).is_equal(10)


func test_a_skill_already_above_the_max_is_never_lowered() -> void:
	var bot := P.bot("a", 10)
	_skill(bot, "Strike").level = 12
	SkillProgress.apply(bot, _uses({"strike": 3}), SkillUseLedger.new(), P.tuning())
	assert_int(_skill(bot, "Strike").level).is_equal(12)


func test_uses_with_no_matching_bot_skill_are_reported_only() -> void:
	var bot := P.bot("a", 10)
	var changes := SkillProgress.apply(bot, _uses({"overload": 9}), SkillUseLedger.new(), P.tuning())
	assert_bool(changes[0].has_bot_skill()).is_false()
	assert_int(changes[0].uses).is_equal(9)
	for s in bot.skills:
		assert_int(s.level).is_equal(1)


func test_levels_are_per_bot() -> void:
	var a := P.bot("a", 10)
	var b := P.bot("b", 5)
	var ledger := SkillUseLedger.new()
	SkillProgress.apply(a, _uses({"strike": 3}), ledger, P.tuning())
	assert_int(_skill(a, "Strike").level).is_equal(2)
	assert_int(_skill(b, "Strike").level).is_equal(1)


## These tests' numbers were worked out under the old fight switches.
func before() -> void:
	Legacy.pin()


func after() -> void:
	Legacy.unpin()

