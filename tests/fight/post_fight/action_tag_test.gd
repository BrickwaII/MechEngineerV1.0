extends GdUnitTestSuite
## Every decision leaves one ActionTag, in order, with the right labels.
const Legacy := preload("res://tests/fight/legacy_switches.gd")

const P := preload("res://tests/fight/post_fight/post_fight_test_helpers.gd")
const H := preload("res://tests/fight/fight_test_helpers.gd")


func _sample() -> Fight:
	var fight := P.fight_for([P.bot("a", 10), P.bot("b", 5)])
	assert_str(P.play(fight, P.sample_steps())).is_empty()
	return fight


func test_sample_fight_ends_after_its_last_step() -> void:
	var fight := _sample()
	assert_bool(fight.is_over()).is_true()
	assert_bool(fight.result().is_victory()).is_true()


func test_every_decision_has_one_tag_in_order() -> void:
	var fight := _sample()
	assert_int(fight.decision_tags.size()).is_equal(fight.action_count)
	for i in fight.decision_tags.size():
		var tag := fight.decision_tags[i]
		assert_int(tag.index).is_equal(i)
		assert_str(tag.short_text()).is_equal(fight.action_tags[i])
		if i > 0:
			assert_int(tag.tick).is_greater_equal(fight.decision_tags[i - 1].tick)


func test_sample_fight_labels() -> void:
	var tags := _sample().decision_tags
	var expected := [
		["a", 10, ["hit_enemy", "first_affordable"]],
		["a", 20, ["hit_enemy", "solo"]],
		["b", 20, ["wait"]],
		["b", 21, ["hit_enemy", "solo"]],
		["a", 30, ["hit_enemy"]],
	]
	assert_int(tags.size()).is_equal(expected.size())
	for i in expected.size():
		assert_str(tags[i].actor_id).is_equal(expected[i][0])
		assert_int(tags[i].tick).is_equal(expected[i][1])
		assert_array(tags[i].labels).contains_exactly(expected[i][2])


func test_tags_record_damage_and_energy() -> void:
	var tags := _sample().decision_tags
	assert_array(tags.map(func(t: ActionTag) -> int: return t.damage)).contains_exactly([15, 10, 0, 22, 15])
	assert_int(tags[0].energy_before_milli).is_equal(7000)
	assert_int(tags[0].energy_cost_milli).is_equal(4000)
	assert_bool(tags[3].after_wait).is_true()
	assert_int(tags[2].target_side).is_equal(ActionTag.NO_SIDE)
	assert_int(tags[0].target_side).is_equal(Combatant.Side.ENEMY)


func test_per_bot_list_is_complete_and_ordered() -> void:
	var report := PostFight.apply(_sample(), [P.bot("a", 10), P.bot("b", 5)], null, P.tuning())
	assert_array(report.bot("a").tags.map(func(t: ActionTag) -> int: return t.index)).contains_exactly([0, 1, 4])
	assert_array(report.bot("b").tags.map(func(t: ActionTag) -> int: return t.index)).contains_exactly([2, 3])


func test_a_long_random_fight_tags_every_decision() -> void:
	var squad: Array[SquadMemberSummary] = [
		H.member("x", H.stats(40, 6, 3, 6, 12)), H.member("y", H.stats(30, 5, 2, 8, 9))]
	var fight := HeadlessFightRunner.run(H.request(squad, 3), 9, RandomFightPolicy.new())
	assert_bool(fight.is_over()).is_true()
	assert_int(fight.decision_tags.size()).is_equal(fight.action_count)
	assert_int(fight.decision_tags.size()).is_equal(fight.action_tags.size())


func test_labels_show_in_the_fight_log() -> void:
	assert_str(_sample().log_text()).contains("  tags: hit_enemy, first_affordable")


# Label rules on hand-built tags.

func _tag(actor: String, side: int, kind: int, target := "", target_side := ActionTag.NO_SIDE, damage := 0, energy := 0, cost := 0, after_wait := false) -> ActionTag:
	var t := ActionTag.new()
	t.actor_id = actor
	t.actor_side = side
	t.kind = kind
	t.skill_id = "s"
	t.target_id = target
	t.target_side = target_side
	t.damage = damage
	t.energy_before_milli = energy
	t.energy_cost_milli = cost
	t.after_wait = after_wait
	return t


const PL := Combatant.Side.PLAYER
const EN := Combatant.Side.ENEMY
const SK := FightAction.Kind.SKILL


func _labels(tag: ActionTag, earlier: Array[ActionTag] = []) -> Array[String]:
	return ActionTag.compute_labels(tag, earlier)


func test_self_target_and_ally_target() -> void:
	assert_array(_labels(_tag("a", PL, SK, "a", PL))).contains_exactly(["self_target"])
	assert_array(_labels(_tag("a", PL, SK, "b", PL))).contains_exactly(["ally_target"])


func test_a_hit_for_no_damage_is_not_hit_enemy() -> void:
	assert_array(_labels(_tag("a", PL, SK, "e", EN, 0))).is_empty()


func test_solo_needs_no_ally_between_and_ignores_enemies() -> void:
	var first := _tag("a", PL, SK, "e", EN, 1)
	var enemy := _tag("e", EN, SK, "a", PL, 1)
	var ally := _tag("b", PL, SK, "e", EN, 1)
	var now := _tag("a", PL, SK, "e", EN, 1)
	assert_array(_labels(now, [first, enemy])).contains(["solo"])
	assert_array(_labels(now, [first, ally, enemy])).not_contains(["solo"])
	assert_array(_labels(now, [])).not_contains(["solo"])


func test_first_affordable() -> void:
	var cost := 4000
	# First decision with a costly skill.
	assert_array(_labels(_tag("a", PL, SK, "e", EN, 1, 5000, cost))).contains(["first_affordable"])
	# Free skills never count.
	assert_array(_labels(_tag("a", PL, SK, "e", EN, 1, 5000, 0))).not_contains(["first_affordable"])
	# Could not afford it last turn: counts. Could: does not.
	var poor := _tag("a", PL, SK, "e", EN, 1, 3000, 0)
	var rich := _tag("a", PL, SK, "e", EN, 1, 6000, 0)
	assert_array(_labels(_tag("a", PL, SK, "e", EN, 1, 5000, cost), [poor])).contains(["first_affordable"])
	assert_array(_labels(_tag("a", PL, SK, "e", EN, 1, 5000, cost), [rich])).not_contains(["first_affordable"])
	# The turn that ends a wait does not count.
	assert_array(_labels(_tag("a", PL, SK, "e", EN, 1, 5000, cost, true), [poor])).not_contains(["first_affordable"])


## These tests' numbers were worked out under the old fight switches.
func before() -> void:
	Legacy.pin()


func after() -> void:
	Legacy.unpin()

