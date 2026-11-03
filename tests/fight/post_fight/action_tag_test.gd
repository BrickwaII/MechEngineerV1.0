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



# --- Action tags (combat rework S6) -------------------------------------------

const T := preload("res://tests/fight/intent/intent_test_helpers.gd")


## Allies "a" and "b" (fast, big batteries, a's turn first) against one slow,
## sturdy foe; the squad holds Strike, Shred, Heavy Strike, Brace and Shield.
static func _kit_fight() -> Fight:
	var tuning := CombatTuning.load_default()
	tuning.player_skills.assign(["strike", "shred", "heavy_strike", "brace", "shield"])
	var ally := T.stats(60, 12, 3, 11, 20)
	return T.fight(
		[{"id": "a", "stats": ally}, {"id": "b", "stats": ally}],
		[{"id": "foe#1", "stats": T.stats(400, 6, 4, 3, 10), "skills": ["strike"]}], tuning)


## Submits `action` for the unit whose turn it is, which must be `actor_id`;
## returns its ActionTag.
func _decide(fight: Fight, actor_id: String, action: FightAction) -> ActionTag:
	assert_str(fight.advance().id).is_equal(actor_id)
	assert_str(fight.submit(action)).is_empty()
	return fight.decision_tags[-1]


func test_a_strike_is_offense() -> void:
	var tag := _decide(_kit_fight(), "a", FightAction.use("strike", "foe#1"))
	assert_array(tag.tags).contains_exactly(["offense"])
	assert_array(tag.labels).contains(["hit_enemy"])


func test_shred_is_a_setup_and_the_hit_that_uses_it_a_payoff() -> void:
	var fight := _kit_fight()
	assert_array(_decide(fight, "a", FightAction.use("shred", "foe#1")).tags).contains_exactly(["offense", "setup"])
	var cash := _decide(fight, "b", FightAction.use("heavy_strike", "foe#1"))
	assert_array(cash.tags).contains_exactly(["offense", "payoff"])


func test_a_plain_strike_on_an_exposed_foe_is_a_payoff_too() -> void:
	var fight := _kit_fight()
	_decide(fight, "a", FightAction.use("shred", "foe#1"))
	assert_array(_decide(fight, "b", FightAction.use("strike", "foe#1")).tags).contains_exactly(["offense", "payoff"])


func test_a_heavy_strike_with_nothing_to_cash_is_only_offense() -> void:
	assert_array(_decide(_kit_fight(), "a", FightAction.use("heavy_strike", "foe#1")).tags).contains_exactly(["offense"])


func test_brace_is_defense_on_self_and_shield_defense_on_an_ally() -> void:
	var fight := _kit_fight()
	assert_array(_decide(fight, "a", FightAction.use("brace", "a")).tags).contains_exactly(["defense", "self"])
	assert_array(_decide(fight, "b", FightAction.use("shield", "a")).tags).contains_exactly(["defense", "ally"])


func test_a_wait_is_banked() -> void:
	var fight := _kit_fight()
	fight.advance()
	fight.combatant("a").energy_milli = 0
	assert_str(fight.submit(FightAction.wait_for("heavy_strike"))).is_empty()
	assert_array(fight.decision_tags[-1].tags).contains_exactly(["banked"])
	assert_array(fight.decision_tags[-1].labels).contains(["wait"])


func test_hitting_a_foe_that_has_committed_a_hit_is_reactive() -> void:
	var fight := _kit_fight()
	var foe := fight.combatant("foe#1")
	foe.committed = UnitIntent.new(foe.id, UnitIntent.Kind.ATTACK, FightAction.use("strike", "b"))
	assert_array(_decide(fight, "a", FightAction.use("strike", "foe#1")).tags).contains_exactly(["offense", "reactive"])


func test_a_defense_on_a_unit_an_intent_attacks_is_reactive() -> void:
	var fight := _kit_fight()
	var foe := fight.combatant("foe#1")
	foe.intent = UnitIntent.new(foe.id, UnitIntent.Kind.ATTACK, FightAction.use("strike", "b"))
	assert_array(_decide(fight, "a", FightAction.use("brace", "a")).tags).contains_exactly(["defense", "self"])
	assert_array(_decide(fight, "b", FightAction.use("brace", "b")).tags).contains_exactly(["defense", "self", "reactive"])


func test_an_actions_data_tags_are_carried() -> void:
	var fight := _kit_fight()
	fight.combatant("a").skill("strike").tags.assign(["payoff"])
	assert_array(_decide(fight, "a", FightAction.use("strike", "foe#1")).tags).contains_exactly(["offense", "payoff"])


func test_tags_are_on_the_decision_event_and_not_in_the_log_text() -> void:
	var fight := _kit_fight()
	var tag := _decide(fight, "a", FightAction.use("shred", "foe#1"))
	assert_array(fight.last_events[0].tags).is_equal(tag.tags)
	assert_bool(fight.log_text().contains("setup")).is_false()


func test_has_label_matches_labels_and_tags() -> void:
	var tag := _decide(_kit_fight(), "a", FightAction.use("shred", "foe#1"))
	assert_bool(tag.has_label("hit_enemy")).is_true()
	assert_bool(tag.has_label("setup")).is_true()
	assert_bool(tag.has_tag("setup")).is_true()
	assert_bool(tag.has_tag("hit_enemy")).is_false()
	assert_bool(tag.has_label("defense")).is_false()


func test_a_drift_rule_may_name_an_action_tag() -> void:
	for label_and_count: Array in [["setup", 0], ["nonsense", 1]]:
		var tuning := PostFightTuning.load_default()
		var rule := PostFightTuning.DriftRule.new()
		rule.label = label_and_count[0]
		rule.pole = "supportive"
		tuning.drift_rules.append(rule)
		assert_array(tuning.validate().filter(func(p: String) -> bool: return p.contains("drift rule label"))).has_size(
			label_and_count[1])


func test_every_shipped_action_tag_is_known() -> void:
	var skills := CombatTuning.load_default().skills
	for id: String in skills:
		for t in skills[id].tags:
			assert_array(ActionTag.TAGS).contains([t])


func test_an_unknown_data_tag_is_refused() -> void:
	var skill := CombatSkill.from_dict("x", {"name": "X", "energy_cost": 1, "power_percent": 100, "tags": ["sneaky"]})
	assert_array(skill.validate().filter(func(p: String) -> bool: return p.contains("unknown tag"))).has_size(1)
