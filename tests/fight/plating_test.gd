extends GdUnitTestSuite
## Plating and Stagger (combat rework S4): every hit strips a pip, a matching
## damage type strips two; at zero the enemy is Staggered (wait cancelled,
## knocked back, its next turn lost, bonus damage) and then recovers its plating.

const H := preload("res://tests/fight/fight_test_helpers.gd")
const V := preload("res://tests/fight/variants/variant_test_helpers.gd")

const FLURRY := "test_flurry"
const ION_SHOT := "test_ion_shot"
const ION := "test_ion"


## The default tuning plus two test-only actions: a three-hit Flurry and an
## ion-typed single shot. The ally fights with strike, heavy_strike and both.
static func _tuning(base: CombatTuning = null) -> CombatTuning:
	var t := base if base != null else CombatTuning.load_default()
	var flurry := CombatSkill.new(FLURRY, "Flurry", 1, 40)
	flurry.hit_count = 3
	t.skills[FLURRY] = flurry
	var ion := CombatSkill.new(ION_SHOT, "Ion Shot", 1, 100)
	ion.damage_type = ION
	t.skills[ION_SHOT] = ion
	t.player_skills.assign(["strike", "heavy_strike", FLURRY, ION_SHOT])
	return t


## A fast ally against one slow foe with `plating` pips, weak to ions.
static func _fight(plating := 3, tuning: CombatTuning = null, foe_elasticity := 0) -> Fight:
	tuning = tuning if tuning != null else _tuning()
	var foe := H.enemy_def("Plated Foe", H.stats(200, 4, 2, 3, 10, foe_elasticity), ["strike", "heavy_strike"])
	foe["archetype"] = "test_plated"
	var table := H.table({"foe": foe}, "foe")
	table.archetypes = EnemyArchetypeTable.from_dict({"archetypes": {
		"test_plated": {"name": "Test Plated", "plating": plating, "plating_weakness": ION}}})
	var squad: Array[SquadMemberSummary] = [H.member("ally", H.stats(200, 10, 2, 11, 20))]
	return Fight.new(H.request(squad), 1, tuning, table)


static func _foe(fight: Fight) -> Combatant:
	return fight.combatant("foe#1")


static func _kinds(fight: Fight) -> Array:
	return fight.last_events.map(func(e: FightEvent) -> FightEvent.Kind: return e.kind)


func test_an_archetype_gives_the_enemy_its_plating() -> void:
	var foe := _foe(_fight(3))
	assert_int(foe.plating).is_equal(3)
	assert_int(foe.max_plating).is_equal(3)
	assert_str(foe.plating_weakness).is_equal(ION)
	assert_bool(foe.staggered).is_false()


func test_an_enemy_without_an_archetype_is_unplated() -> void:
	var fight := H.duel(H.stats(50, 5, 0, 11, 10), H.stats(50, 1, 0, 3, 10))
	assert_int(_foe(fight).plating).is_equal(0)


func test_a_multi_hit_action_staggers_a_plated_enemy_a_single_heavy_hit_does_not() -> void:
	var heavy := _fight(3)
	assert_object(heavy.advance()).is_same(heavy.combatant("ally"))
	assert_str(heavy.submit(FightAction.use("heavy_strike", "foe#1"))).is_empty()
	assert_int(_foe(heavy).plating).is_equal(2)
	assert_bool(_foe(heavy).staggered).is_false()
	assert_array(_kinds(heavy)).not_contains([FightEvent.Kind.STAGGER])

	var flurry := _fight(3)
	flurry.advance()
	assert_str(flurry.submit(FightAction.use(FLURRY, "foe#1"))).is_empty()
	assert_int(_foe(flurry).plating).is_equal(0)
	assert_bool(_foe(flurry).staggered).is_true()
	assert_array(_kinds(flurry)).contains([FightEvent.Kind.STAGGER])


func test_every_hit_of_a_multi_hit_action_lands_and_strips_a_pip() -> void:
	var fight := _fight(5)
	fight.advance()
	fight.submit(FightAction.use(FLURRY, "foe#1"))
	var hits := fight.last_events.filter(func(e: FightEvent) -> bool: return e.kind == FightEvent.Kind.HIT)
	var strips := fight.last_events.filter(func(e: FightEvent) -> bool: return e.kind == FightEvent.Kind.PLATING)
	assert_int(hits.size()).is_equal(3)
	assert_int(strips.size()).is_equal(3)
	assert_array(strips.map(func(e: FightEvent) -> int: return e.plating_after)).is_equal([4, 3, 2])
	assert_int(_foe(fight).plating).is_equal(2)


func test_a_matching_damage_type_strips_two_pips() -> void:
	var fight := _fight(3)
	fight.advance()
	fight.submit(FightAction.use(ION_SHOT, "foe#1"))
	assert_int(_foe(fight).plating).is_equal(1)
	var strip: FightEvent = fight.last_events.filter(func(e: FightEvent) -> bool: return e.kind == FightEvent.Kind.PLATING)[0]
	assert_int(strip.amount).is_equal(2)


func test_stripping_never_takes_more_pips_than_are_left() -> void:
	var fight := _fight(1)
	fight.advance()
	fight.submit(FightAction.use(ION_SHOT, "foe#1"))
	var strip: FightEvent = fight.last_events.filter(func(e: FightEvent) -> bool: return e.kind == FightEvent.Kind.PLATING)[0]
	assert_int(strip.amount).is_equal(1)
	assert_bool(_foe(fight).staggered).is_true()


func test_stagger_knocks_the_enemy_back_on_the_timeline() -> void:
	var fight := _fight(1)
	fight.advance()
	var foe := _foe(fight)
	foe.gauge = fight.timeline.threshold - 1
	var gauge := foe.gauge
	fight.submit(FightAction.use("strike", foe.id))
	var expected := fight.timeline.threshold * fight.tuning.stagger.knockback_percent / 100
	assert_int(expected).is_greater(0)
	assert_int(foe.gauge).is_equal(gauge - expected)
	var stagger: FightEvent = fight.last_events.filter(func(e: FightEvent) -> bool: return e.kind == FightEvent.Kind.STAGGER)[0]
	assert_int(stagger.amount).is_equal(expected)


func test_knockback_never_takes_the_gauge_below_empty() -> void:
	var fight := _fight(1)
	fight.advance()
	_foe(fight).gauge = 5
	fight.submit(FightAction.use("strike", "foe#1"))
	assert_int(_foe(fight).gauge).is_equal(0)


func test_hits_on_a_staggered_enemy_deal_bonus_damage() -> void:
	var plain := _fight(9)
	plain.advance()
	var before := _foe(plain).hp
	plain.submit(FightAction.use("strike", "foe#1"))
	var normal := before - _foe(plain).hp

	var broken := _fight(1)
	broken.advance()
	broken.submit(FightAction.use(ION_SHOT, "foe#1"))
	assert_bool(_foe(broken).staggered).is_true()
	broken.advance()
	before = _foe(broken).hp
	broken.submit(FightAction.use("strike", "foe#1"))
	var bonus := broken.tuning.stagger.damage_bonus_percent
	assert_int(bonus).is_greater(0)
	assert_int(before - _foe(broken).hp).is_greater(normal)
	var ally := broken.combatant("ally")
	var expected := DamageRules.damage(ally.stats, _foe(broken).stats, ally.skill("strike"), broken.tuning, bonus)
	assert_int(before - _foe(broken).hp).is_equal(expected)


func test_the_hits_after_the_break_in_one_action_get_the_bonus() -> void:
	var fight := _fight(2)
	fight.advance()
	fight.submit(FightAction.use(FLURRY, "foe#1"))
	var hits := fight.last_events.filter(func(e: FightEvent) -> bool: return e.kind == FightEvent.Kind.HIT)
	assert_int(hits[2].amount).is_greater(hits[0].amount)
	assert_int(hits[0].amount).is_equal(hits[1].amount)


func test_a_staggered_enemy_loses_its_next_turn_and_recovers_its_plating() -> void:
	var fight := _fight(1)
	fight.advance()
	fight.submit(FightAction.use("strike", "foe#1"))
	var foe := _foe(fight)
	assert_bool(foe.staggered).is_true()
	var recovered := false
	for i in 40:
		var actor := fight.advance()
		assert_object(actor).is_not_same(foe)
		if not foe.staggered:
			recovered = true
			break
		fight.submit(FightAction.use("strike", foe.id) if foe.plating == 0 else FightAction.wait_for("strike"))
	assert_bool(recovered).is_true()
	assert_int(foe.plating).is_equal(foe.max_plating)
	assert_bool(fight.log_text().contains("recovers from the Stagger")).is_true()


func test_recovery_raises_an_event_and_spends_the_turn_without_a_decision() -> void:
	var fight := _fight(1)
	fight.advance()
	fight.submit(FightAction.use("strike", "foe#1"))
	var foe := _foe(fight)
	foe.gauge = fight.timeline.threshold
	var count := fight.action_count
	var events: Array[FightEvent] = []
	fight.event_raised.connect(func(e: FightEvent) -> void: events.append(e))
	var next := fight.advance()
	assert_object(next).is_same(fight.combatant("ally"))
	assert_int(fight.action_count).is_equal(count)
	# RECOVER, then (S5) the archetype enemy announces its new intent.
	assert_int(events.size()).is_equal(2)
	assert_int(events[0].kind).is_equal(FightEvent.Kind.RECOVER)
	assert_int(events[0].amount).is_equal(1)
	assert_int(events[0].plating_after).is_equal(1)
	assert_int(events[1].kind).is_equal(FightEvent.Kind.INTENT_CHANGED)
	assert_str(events[1].reason).is_equal("recovered")
	assert_bool(foe.staggered).is_false()
	assert_int(foe.gauge).is_less(fight.timeline.threshold)


func test_stagger_cancels_a_wind_up() -> void:
	var fight := _fight(1)
	var foe := _foe(fight)
	foe.begin_wait(foe.max_energy_milli)
	assert_bool(foe.is_waiting()).is_true()
	fight.advance()
	fight.submit(FightAction.use("strike", foe.id))
	assert_bool(foe.is_waiting()).is_false()
	assert_bool(fight.log_text().contains("its wait is cancelled")).is_true()


func test_a_staggered_enemy_has_no_intent() -> void:
	var fight := _fight(1)
	var planner := IntentPlanner.new()
	fight.advance()
	assert_object(planner.plan(fight, _foe(fight))).is_not_null()
	fight.submit(FightAction.use("strike", "foe#1"))
	assert_object(planner.plan(fight, _foe(fight))).is_null()
	assert_bool(planner.plan_all(fight).has("foe#1")).is_false()


func test_recover_percent_zero_leaves_the_enemy_unplated() -> void:
	var t := _tuning()
	t.stagger.recover_percent = 0
	var fight := _fight(1, t)
	fight.advance()
	fight.submit(FightAction.use("strike", "foe#1"))
	var foe := _foe(fight)
	foe.gauge = fight.timeline.threshold
	fight.advance()
	assert_bool(foe.staggered).is_false()
	assert_int(foe.plating).is_equal(0)
	fight.submit(FightAction.use("strike", foe.id))
	assert_bool(foe.staggered).is_false()
	assert_array(_kinds(fight)).not_contains([FightEvent.Kind.PLATING])


func test_elasticity_stagger_recovery_cuts_the_knockback() -> void:
	var t := _tuning(V.tuning_with(FightVariants.ELASTICITY, FightVariants.ELASTICITY_STAGGER))
	var per := t.variants.param_int(FightVariants.ELASTICITY, "cut_percent_per_point")
	var most := t.variants.param_int(FightVariants.ELASTICITY, "max_cut_percent")
	var stats := H.stats(1, 0, 0, 1, 1, 2)
	assert_int(ElasticityRules.stagger_knockback_cut_percent(stats, t)).is_equal(2 * per)
	assert_int(ElasticityRules.stagger_knockback_cut_percent(H.stats(1, 0, 0, 1, 1, 99), t)).is_equal(most)
	assert_int(ElasticityRules.stagger_knockback_cut_percent(stats, CombatTuning.load_default())).is_equal(0)
	var full := t.stagger.knockback_gauge(H.stats(1, 0, 0, 1, 1, 0), 1000, t)
	assert_int(t.stagger.knockback_gauge(stats, 1000, t)).is_equal(full * (100 - 2 * per) / 100)

	var fight := _fight(1, t, 2)
	fight.advance()
	var foe := _foe(fight)
	foe.gauge = fight.timeline.threshold - 1
	fight.submit(FightAction.use("strike", foe.id))
	assert_int(foe.gauge).is_equal(fight.timeline.threshold - 1 - t.stagger.knockback_gauge(foe.stats, fight.timeline.threshold, t))


func test_preview_copies_plating_and_matches_the_resolved_hits() -> void:
	var fight := _fight(2)
	fight.advance()
	var copy := FightCopy.of(fight)
	assert_int(copy.combatant("foe#1").plating).is_equal(2)
	assert_int(copy.combatant("foe#1").max_plating).is_equal(2)
	assert_str(copy.combatant("foe#1").plating_weakness).is_equal(ION)
	var action := FightAction.use(FLURRY, "foe#1")
	var choice := FightPreview.new().preview_choice(fight, action)
	var hp := _foe(fight).hp
	fight.submit(action)
	assert_int(choice.effect_on("foe#1").damage.value).is_equal(hp - _foe(fight).hp)
	# The live fight was not touched by the preview before the submit.
	assert_bool(_foe(fight).staggered).is_true()


func test_a_staggered_unit_is_copied_staggered() -> void:
	var fight := _fight(1)
	fight.advance()
	fight.submit(FightAction.use("strike", "foe#1"))
	fight.advance()
	var copy := FightCopy.of(fight)
	assert_bool(copy.combatant("foe#1").staggered).is_true()
	assert_int(copy.combatant("foe#1").plating).is_equal(0)


func test_a_plated_fight_replays_identically() -> void:
	var a := _play(_fight(3))
	var b := _play(_fight(3))
	assert_str(a).is_equal(b)
	assert_bool(a.contains("Staggered")).is_true()


func _play(fight: Fight) -> String:
	var policy := IntentFightPolicy.new()
	var rng := RandomNumberGenerator.new()
	for i in 60:
		var actor := fight.advance()
		if actor == null:
			break
		var action := FightAction.use(FLURRY, "foe#1") if actor.side == Combatant.Side.PLAYER and actor.can_afford(actor.skill(FLURRY)) \
			else policy.choose(fight, actor, rng)
		if action == null or not fight.check_action(action).is_empty():
			action = SimpleFightPolicy.new().choose(fight, actor, rng)
		fight.submit(action)
	return fight.log_text()


func test_stagger_rules_load_and_validate() -> void:
	var r := StaggerRules.from_dict({})
	assert_array(r.validate()).is_empty()
	assert_array(CombatTuning.load_default().stagger.validate()).is_empty()
	assert_int(r.pips_stripped("", "")).is_equal(r.pips_per_hit)
	assert_int(r.pips_stripped(ION, ION)).is_equal(r.pips_per_matching_hit)
	assert_int(r.pips_stripped("", ION)).is_equal(r.pips_per_hit)
	assert_int(r.recovered_plating(3)).is_equal(3)
	var bad := StaggerRules.from_dict({"pips_per_hit": 2, "pips_per_matching_hit": 1, "knockback_percent": -1,
		"damage_bonus_percent": -1, "recover_percent": 101})
	assert_int(bad.validate().size()).is_equal(4)


func test_an_archetype_weakness_needs_plating() -> void:
	var a := EnemyArchetype.from_dict("x", {"name": "X", "plating_weakness": ION})
	assert_str(a.plating_weakness).is_equal(ION)
	assert_array(a.validate()).contains(["archetype x has a plating_weakness but no plating"])
	assert_array(EnemyArchetype.from_dict("y", {"name": "Y", "plating": 2, "plating_weakness": ION}).validate()).is_empty()


func test_the_pipeline_total_counts_the_break_inside_a_multi_hit_action() -> void:
	var fight := _fight(2)
	var ally := fight.advance()
	var foe := _foe(fight)
	var flurry := ally.skill(FLURRY)
	var hits := DamagePipeline.hits(ally, foe, flurry, fight.tuning)
	assert_int(hits.size()).is_equal(3)
	assert_int(hits[2].stagger_bonus_percent).is_equal(fight.tuning.stagger.damage_bonus_percent)
	assert_int(hits[0].stagger_bonus_percent).is_equal(0)
	var total := DamageRules.action_damage_to(ally, foe, flurry, fight.tuning)
	var hp := foe.hp
	fight.submit(FightAction.use(FLURRY, foe.id))
	assert_int(hp - foe.hp).is_equal(total)
	# The planner's estimate is the pipeline's: no plating left on the live foe was touched.
	assert_int(foe.plating).is_equal(0)
