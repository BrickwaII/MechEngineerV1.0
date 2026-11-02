extends GdUnitTestSuite
## Brace (combat rework S4, user decision brace-rule): absorbs damage up to a
## Defense-based value, over any number of hits, until the bot's next action.
## No reflect. Shield Ally keeps its percent guard and reflect.

const H := preload("res://tests/fight/fight_test_helpers.gd")


static func _tuning() -> CombatTuning:
	var t := CombatTuning.load_default()
	t.player_skills.assign(["strike", "brace", "shield"])
	return t


## A fast ally (Defense `defense`) against a slower foe that hits hard enough
## to get past a little of the Brace.
static func _fight(defense := 6, foe_attack := 12) -> Fight:
	var t := _tuning()
	var table := H.table({"foe": H.enemy_def("Foe", H.stats(200, foe_attack, 0, 5, 20), ["strike", "heavy_strike"])}, "foe")
	var squad: Array[SquadMemberSummary] = [H.member("ally", H.stats(200, 5, defense, 11, 20))]
	return Fight.new(H.request(squad), 1, t, table)


## Runs time until the foe is ready, playing the ally with Strike meanwhile
## (which would end a Brace), and returns it. Use it only after the ally's
## Brace when no ally turn falls in between.
static func _foe_turn(fight: Fight) -> Combatant:
	var actor := fight.advance()
	assert(actor.side == Combatant.Side.ENEMY, "the ally acted again first")
	return actor


static func _brace_up(fight: Fight) -> Combatant:
	var ally := fight.advance()
	assert(ally.id == "ally")
	assert(fight.submit(FightAction.use("brace", ally.id)).is_empty())
	return ally


func test_brace_is_an_absorb_action_with_its_id() -> void:
	var brace := CombatTuning.load_default().skill("brace")
	assert_bool(brace.is_absorb()).is_true()
	assert_bool(brace.is_guard()).is_false()
	assert_str(brace.target).is_equal(CombatSkill.TARGET_SELF)
	assert_int(brace.energy_cost).is_greater(0)


func test_brace_absorbs_defense_times_its_power() -> void:
	var fight := _fight(6)
	var ally := _brace_up(fight)
	var brace := ally.skill("brace")
	assert_int(ally.brace_absorb).is_equal(6 * brace.power_percent / 100)
	assert_int(ally.brace_absorb).is_equal(DamageRules.brace_absorb(ally.stats, brace))
	var raised: FightEvent = fight.last_events.filter(func(e: FightEvent) -> bool: return e.kind == FightEvent.Kind.BRACE)[0]
	assert_int(raised.amount).is_equal(ally.brace_absorb)


func test_more_defense_absorbs_more() -> void:
	var brace := CombatTuning.load_default().skill("brace")
	assert_int(DamageRules.brace_absorb(H.stats(1, 1, 10, 1, 1), brace)).is_greater(
		DamageRules.brace_absorb(H.stats(1, 1, 4, 1, 1), brace))


func test_a_hit_on_a_braced_unit_is_absorbed_and_spends_the_brace() -> void:
	var fight := _fight(6, 12)
	var ally := _brace_up(fight)
	var absorb := ally.brace_absorb
	var foe := _foe_turn(fight)
	var unbraced := DamageRules.damage_before_brace(foe, ally, foe.skill("strike"), fight.tuning)
	assert_int(unbraced).is_greater(absorb)
	var hp := ally.hp
	fight.submit(FightAction.use("strike", ally.id))
	assert_int(hp - ally.hp).is_equal(unbraced - absorb)
	assert_int(ally.brace_absorb).is_equal(0)
	var hit: FightEvent = fight.last_events.filter(func(e: FightEvent) -> bool: return e.kind == FightEvent.Kind.HIT)[0]
	assert_int(hit.absorbed).is_equal(absorb)


func test_a_small_hit_is_absorbed_whole_and_the_rest_lasts() -> void:
	var fight := _fight(20, 3)
	var ally := _brace_up(fight)
	var absorb := ally.brace_absorb
	var foe := _foe_turn(fight)
	var unbraced := DamageRules.damage_before_brace(foe, ally, foe.skill("strike"), fight.tuning)
	assert_int(unbraced).is_less(absorb)
	var hp := ally.hp
	fight.submit(FightAction.use("strike", ally.id))
	assert_int(ally.hp).is_equal(hp)
	assert_int(ally.brace_absorb).is_equal(absorb - unbraced)


func test_brace_expires_on_the_bots_next_action() -> void:
	var fight := _fight(20, 3)
	var ally := _brace_up(fight)
	assert_int(ally.brace_absorb).is_greater(0)
	var left := ally.brace_absorb
	var actor := fight.advance()
	while actor != ally:
		fight.submit(FightAction.use("strike", ally.id))
		left = ally.brace_absorb
		actor = fight.advance()
	# Still bracing while it is the bot's turn to choose.
	assert_int(ally.brace_absorb).is_equal(left)
	fight.submit(FightAction.use("strike", "foe#1"))
	assert_int(ally.brace_absorb).is_equal(0)
	var ended: Array = fight.last_events.filter(func(e: FightEvent) -> bool: return e.kind == FightEvent.Kind.BRACE_END)
	assert_int(ended.size()).is_equal(1)
	# Raised as the action begins: right after its SKILL event.
	assert_int(fight.last_events[1].kind).is_equal(FightEvent.Kind.BRACE_END)
	if left > 0:
		assert_int(ended[0].amount).is_equal(left)
	assert_bool(fight.log_text().contains("Brace ends")).is_true()


func test_a_wait_also_ends_the_brace() -> void:
	var fight := _fight(20, 3)
	var ally := _brace_up(fight)
	ally.brace_absorb = 5
	ally.gauge = fight.timeline.threshold * 10
	assert_object(fight.advance()).is_same(ally)
	fight.submit(FightAction.wait_for("strike"))
	assert_int(ally.brace_absorb).is_equal(0)


func test_bracing_again_replaces_rather_than_stacks() -> void:
	var fight := _fight(6)
	var ally := _brace_up(fight)
	var first := ally.brace_absorb
	ally.gauge = fight.timeline.threshold * 10
	ally.energy_milli = ally.max_energy_milli
	assert_object(fight.advance()).is_same(ally)
	fight.submit(FightAction.use("brace", ally.id))
	assert_int(ally.brace_absorb).is_equal(first)


func test_brace_has_no_reflect_at_any_rank() -> void:
	var t := CombatTuning.load_default()
	for rank in range(1, t.skill_ranks.max_rank() + 1):
		assert_int(t.skill_at("brace", rank).reflect_percent).is_equal(0)
	var top := t.skill_at("shield", t.skill_ranks.max_rank())
	assert_int(top.reflect_percent).is_greater(0)
	assert_bool(top.is_guard()).is_true()


func test_a_higher_rank_absorbs_more() -> void:
	var t := CombatTuning.load_default()
	var stats := H.stats(1, 1, 10, 1, 1)
	assert_int(DamageRules.brace_absorb(stats, t.skill_at("brace", t.skill_ranks.max_rank()))).is_greater(
		DamageRules.brace_absorb(stats, t.skill_at("brace", 1)))


func test_shield_ally_stays_a_percent_guard() -> void:
	var fight := _fight(6)
	var ally := fight.advance()
	fight.submit(FightAction.use("shield", ally.id))
	assert_int(ally.guard_percent).is_equal(ally.skill("shield").power_percent)
	assert_int(ally.brace_absorb).is_equal(0)


func test_the_planner_and_preview_count_the_brace_as_the_fight_resolves_it() -> void:
	var fight := _fight(6, 12)
	var ally := _brace_up(fight)
	var foe := _foe_turn(fight)
	var planner := IntentPlanner.new()
	var intent := planner.plan(fight, foe)
	var preview := FightPreview.new(planner).preview_choice(fight, intent.action)
	var hp := ally.hp
	fight.submit(intent.action)
	assert_int(intent.amount).is_equal(hp - ally.hp)
	assert_int(preview.effect_on(ally.id).damage.value).is_equal(hp - ally.hp)
	assert_bool(preview.brace_changes.has(ally.id)).is_true()


func test_the_brace_badge_shows_the_absorb() -> void:
	var fight := _fight(6)
	var ally := fight.advance()
	var action := FightAction.use("brace", ally.id)
	var choice := FightPreview.new().preview_choice(fight, action)
	var badges := BattleReadout.choice_badges(fight, action, choice)
	assert_int(badges.size()).is_equal(1)
	assert_str(badges[0].kind).is_equal(ArrowBadge.GUARD)
	assert_bool(badges[0].absorb).is_true()
	assert_int(int(badges[0].amount.value)).is_equal(DamageRules.brace_absorb(ally.stats, ally.skill("brace")))
	assert_int(ally.brace_absorb).is_equal(0)


func test_a_braced_unit_is_copied_braced() -> void:
	var fight := _fight(6)
	var ally := _brace_up(fight)
	assert_int(FightCopy.of(fight).combatant(ally.id).brace_absorb).is_equal(ally.brace_absorb)


func test_skill_numbers_report_the_absorb() -> void:
	var t := CombatTuning.load_default()
	var n := SkillNumbers.at_level(H.stats(1, 1, 8, 1, 1), "brace", 1, t, 0)
	assert_str(n.kind).is_equal(SkillNumbers.KIND_ABSORB)
	assert_float(n.value).is_equal(8.0 * t.skill("brace").power_percent / 100.0)


func test_a_brace_badge_reads_as_damage_absorbed_not_a_percent() -> void:
	var badge := ArrowBadge.new("a", "a", ArrowBadge.GUARD, "brace", PreviewValue.of(6))
	badge.absorb = true
	assert_str(badge.text()).is_equal("6")


func test_the_damage_math_shows_the_brace() -> void:
	var fight := _fight(6, 12)
	var ally := _brace_up(fight)
	var foe := _foe_turn(fight)
	var amount := DamageRules.damage_to(foe, ally, foe.skill("strike"), fight.tuning)
	var lines := BattleMath.damage_lines(fight, foe.id, ally.id, "strike", amount)
	var brace_line: Array = lines.filter(func(l: Variant) -> bool: return l is UiFormula and (l as UiFormula).text().contains("Brace"))
	assert_int(brace_line.size()).is_equal(1)
	assert_str((brace_line[0] as UiFormula).text()).ends_with("= %d" % amount)
	assert_int(BattleMath.brace_lines(fight, ally.id, "brace", ally.brace_absorb).size()).is_equal(2)


func test_the_pipeline_brace_step_absorbs_after_the_guard() -> void:
	var fight := _fight(6, 12)
	var ally := _brace_up(fight)
	var foe := _foe_turn(fight)
	ally.guard_percent = 50
	var b := DamagePipeline.run(foe.stats, ally.stats, foe.skill("strike"), fight.tuning, 0, ally)
	assert_int(b.after_guard).is_equal(DamageRules.guarded(b.before_guard, 50, fight.tuning))
	assert_int(b.brace_absorb).is_equal(ally.brace_absorb)
	assert_int(b.absorbed).is_equal(mini(b.after_guard, ally.brace_absorb))
	assert_int(b.final).is_equal(b.after_guard - b.absorbed)


func test_a_multi_hit_action_spends_the_brace_hit_by_hit() -> void:
	var t := _tuning()
	var flurry := CombatSkill.new("test_flurry", "Flurry", 1, 100)
	flurry.hit_count = 3
	t.skills["test_flurry"] = flurry
	var table := H.table({"foe": H.enemy_def("Foe", H.stats(200, 12, 0, 5, 20), ["strike", "test_flurry"])}, "foe")
	var squad: Array[SquadMemberSummary] = [H.member("ally", H.stats(200, 5, 20, 11, 20))]
	var fight := Fight.new(H.request(squad), 1, t, table)
	var ally := _brace_up(fight)
	var foe := _foe_turn(fight)
	foe.energy_milli = foe.max_energy_milli
	var total := DamageRules.action_damage_to(foe, ally, foe.skill("test_flurry"), t)
	var hp := ally.hp
	fight.submit(FightAction.use("test_flurry", ally.id))
	assert_int(hp - ally.hp).is_equal(total)
	var hits := fight.last_events.filter(func(e: FightEvent) -> bool: return e.kind == FightEvent.Kind.HIT)
	assert_int(hits.size()).is_equal(3)
	var absorbed := 0
	for h: FightEvent in hits:
		absorbed += h.absorbed
	# Every hit is soaked in turn from the one Brace (Defense 20 x 100%).
	assert_int(absorbed).is_equal(20 - ally.brace_absorb)
	assert_bool(hits.all(func(h: FightEvent) -> bool: return h.absorbed > 0)).is_true()
