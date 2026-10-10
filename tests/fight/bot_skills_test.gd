extends GdUnitTestSuite
## Bots fight with their own skills: each bot skill's effect_id picks a combat
## skill, the bot's name and level carry over, and the new effects (heal,
## guard, hit all) resolve deterministically.

const H := preload("res://tests/fight/fight_test_helpers.gd")


func _tuning() -> CombatTuning:
	return CombatTuning.load_default()


func _member(id: String, s: UnitStats, skills: Array) -> SquadMemberSummary:
	var entries: Array[Dictionary] = []
	for e: Array in skills:
		entries.append(SquadMemberSummary.make_skill(e[0], e[1], e[2] if e.size() > 2 else 1))
	return SquadMemberSummary.new(id, id.capitalize(), s.hp, s.hp, "test", s, entries)


## `squad` against `count` foes that only Strike, with this fight's tuning.
func _fight(squad: Array[SquadMemberSummary], foe: UnitStats, count := 1, tuning: CombatTuning = null) -> Fight:
	tuning = tuning if tuning != null else _tuning()
	var table := H.table({"foe": H.enemy_def("Foe", foe)}, "foe", count)
	return Fight.new(H.request(squad), 1, tuning, table)


## Advances until `unit_id` must act, every other unit striking the first
## living opponent meanwhile. Returns false if the fight ended first.
func _until(fight: Fight, unit_id: String) -> bool:
	var actor := fight.advance()
	while actor != null and actor.id != unit_id:
		fight.submit(FightAction.use("strike", fight.opponents_of(actor)[0].id))
		actor = fight.advance()
	return actor != null


func test_a_drafted_bots_skills_appear_in_its_combatant() -> void:
	var tuning := _tuning()
	var squad := BotFactory.new(BotTuning.load_default()).build_squad(5)
	var summaries: Array[SquadMemberSummary] = []
	for bot in squad.get_fielded():
		summaries.append(bot.to_summary())
	var fight := _fight(summaries, H.stats(30, 1, 0, 1, 0))
	for bot in squad.get_fielded():
		var c := fight.combatant(bot.id)
		for skill in bot.skills:
			var combat_id := tuning.combat_skill_for_effect(skill.effect_id)
			assert_bool(c.has_skill(combat_id)).is_true()
			assert_str(c.skill(combat_id).display_name).is_equal(skill.display_name)
			assert_int(c.skill(combat_id).level).is_equal(skill.level)
		# Never stuck: a free single-target attack is always there.
		assert_bool(c.skills().any(func(s: CombatSkill) -> bool: return CombatTuning.is_basic_attack(s))).is_true()


func test_every_catalog_skill_has_a_combat_skill() -> void:
	var tuning := _tuning()
	for skill in BotTuning.load_default().skills:
		assert_str(tuning.combat_skill_for_effect(skill.effect_id)).is_not_empty()
		var combat := tuning.skill(tuning.combat_skill_for_effect(skill.effect_id))
		assert_object(combat).is_not_null()
		# The draft shows the catalog's cost; the fight charges the same.
		assert_int(combat.energy_cost).is_equal(skill.energy_cost)


func test_a_support_bot_gets_the_basic_attack_first_and_only_once() -> void:
	var tuning := _tuning()
	var support := _member("spark", H.stats(30, 5, 2, 5, 10), [["Patch Up", "heal_single"], ["Shield Ally", "guard_ally"]])
	assert_array(SquadSkills.ids_for(support, tuning)).is_equal(["strike", "patch_up", "shield"])
	var striker := _member("bolt", H.stats(30, 5, 2, 5, 10), [["Brace", "guard_self"], ["Strike", "damage_single"]])
	assert_array(SquadSkills.ids_for(striker, tuning)).is_equal(["brace", "strike"])


func test_a_member_with_no_skills_fights_with_the_player_skills() -> void:
	var tuning := _tuning()
	assert_array(SquadSkills.ids_for(H.member("old", H.stats(30, 5, 2, 5, 10)), tuning)).is_equal(tuning.player_skills)


func test_enemies_keep_their_table_skills() -> void:
	var squad: Array[SquadMemberSummary] = [_member("spark", H.stats(30, 5, 2, 5, 10), [["Patch Up", "heal_single"]])]
	var table := H.table({"foe": H.enemy_def("Foe", H.stats(30, 5, 0, 1, 10), ["strike", "overload"])}, "foe")
	var fight := Fight.new(H.request(squad), 1, _tuning(), table)
	assert_array(fight.combatant("foe#1").skill_ids).is_equal(["strike", "overload"])
	assert_str(fight.combatant("foe#1").skill("overload").display_name).is_equal("Overload")


func test_level_scales_power_by_the_tunable() -> void:
	var tuning := _tuning()
	tuning.power_percent_per_level = 10
	var squad: Array[SquadMemberSummary] = [
		_member("one", H.stats(30, 10, 0, 5, 10), [["Strike", "damage_single", 1]]),
		_member("three", H.stats(30, 10, 0, 5, 10), [["Strike", "damage_single", 3]]),
	]
	var fight := _fight(squad, H.stats(100, 1, 0, 1, 0), 1, tuning)
	assert_int(fight.combatant("one").skill("strike").power_percent).is_equal(100)
	# Level 3: two levels above 1, +10% each.
	assert_int(fight.combatant("three").skill("strike").power_percent).is_equal(120)
	assert_int(DamageRules.damage(fight.combatant("three").stats, H.stats(100, 1, 0, 1, 0),
		fight.combatant("three").skill("strike"), tuning)).is_equal(12)


func test_using_patch_up_heals_an_ally() -> void:
	var tuning := _tuning()
	var squad: Array[SquadMemberSummary] = [
		_member("medic", H.stats(30, 8, 2, 9, 12), [["Patch Up", "heal_single"]]),
		_member("tank", H.stats(40, 5, 2, 1, 10), [["Strike", "damage_single"]]),
	]
	squad[1].hp = 20
	var fight := _fight(squad, H.stats(30, 1, 0, 1, 0), 1, tuning)
	assert_bool(_until(fight, "medic")).is_true()
	var medic := fight.combatant("medic")
	var energy := medic.energy_milli
	assert_str(fight.submit(FightAction.use("patch_up", "tank"))).is_empty()
	# attack 8 x 100% = 8 hp, cost 3.
	assert_int(fight.combatant("tank").hp).is_equal(28)
	assert_int(medic.energy_milli).is_equal(energy - tuning.skill("patch_up").energy_cost_milli())
	assert_str(fight.log_text()).contains("Medic uses Patch Up on Tank: 8 healed")


func test_patch_up_may_not_target_an_opponent() -> void:
	var squad: Array[SquadMemberSummary] = [_member("medic", H.stats(30, 8, 2, 9, 12), [["Patch Up", "heal_single"]])]
	var fight := _fight(squad, H.stats(30, 1, 0, 1, 0))
	fight.advance()
	assert_str(fight.check_action(FightAction.use("patch_up", "foe#1"))).contains("on an opponent")


func test_brace_blocks_part_of_the_next_hit_only() -> void:
	var tuning := _tuning()
	var squad: Array[SquadMemberSummary] = [_member("anvil", H.stats(60, 5, 0, 10, 10), [["Brace", "guard_self"]])]
	# The foe hits for 20 unguarded (attack 20, defense 0).
	var fight := _fight(squad, H.stats(200, 20, 0, 10, 0), 1, tuning)
	var anvil := fight.advance()
	assert_str(anvil.id).is_equal("anvil")
	assert_str(fight.check_action(FightAction.use("brace", "foe#1"))).contains("only use brace on itself")
	assert_str(fight.submit(FightAction.use("brace", "anvil"))).is_empty()
	assert_int(anvil.guard_percent).is_equal(50)
	var foe := fight.advance()
	assert_str(foe.id).is_equal("foe#1")
	fight.submit(FightAction.use("strike", "anvil"))
	# 50% of 20 blocked.
	assert_int(anvil.hp).is_equal(50)
	assert_int(anvil.guard_percent).is_equal(0)
	assert_str(fight.log_text()).contains("10 damage (50% blocked)")
	# The guard is used up: the next hit lands in full.
	fight.advance()
	fight.submit(FightAction.use("strike", "foe#1"))
	fight.advance()
	fight.submit(FightAction.use("strike", "anvil"))
	assert_int(anvil.hp).is_equal(30)


func test_shield_ally_blocks_part_of_an_allys_next_hit() -> void:
	var tuning := _tuning()
	var squad: Array[SquadMemberSummary] = [
		_member("spark", H.stats(30, 5, 0, 20, 10), [["Shield Ally", "guard_ally"]]),
		_member("bolt", H.stats(60, 5, 0, 1, 10), [["Strike", "damage_single"]]),
	]
	var fight := _fight(squad, H.stats(200, 20, 0, 10, 0), 1, tuning)
	assert_str(fight.advance().id).is_equal("spark")
	assert_str(fight.check_action(FightAction.use("shield", "foe#1"))).contains("on an opponent")
	assert_str(fight.submit(FightAction.use("shield", "bolt"))).is_empty()
	var bolt := fight.combatant("bolt")
	assert_int(bolt.guard_percent).is_equal(40)
	# Advance to the foe, letting spark strike meanwhile.
	assert_bool(_until(fight, "foe#1")).is_true()
	fight.submit(FightAction.use("strike", "bolt"))
	# 40% of 20 blocked.
	assert_int(bolt.hp).is_equal(48)
	assert_int(bolt.guard_percent).is_equal(0)


func test_guard_never_blocks_more_than_the_cap_and_never_drops_below_min_damage() -> void:
	var tuning := _tuning()
	tuning.max_guard_percent = 80
	tuning.power_percent_per_level = 100
	var squad: Array[SquadMemberSummary] = [_member("anvil", H.stats(60, 5, 0, 10, 10), [["Brace", "guard_self", 5]])]
	var fight := _fight(squad, H.stats(200, 20, 0, 10, 0), 1, tuning)
	# 50% at +100% per level for 4 levels would be 250%; capped.
	assert_int(fight.combatant("anvil").skill("brace").power_percent).is_equal(80)
	assert_int(DamageRules.guarded(1, 80, tuning)).is_equal(tuning.min_damage)


func test_arc_sweep_hits_every_living_opponent() -> void:
	var squad: Array[SquadMemberSummary] = [_member("cog", H.stats(30, 10, 0, 10, 12), [["Arc Sweep", "damage_all"]])]
	var fight := _fight(squad, H.stats(30, 1, 0, 1, 0), 3)
	var cog := fight.advance()
	assert_str(fight.submit(FightAction.use("arc_sweep", "foe#2"))).is_empty()
	# attack 10 x 60% = 6 each.
	for foe in fight.living(Combatant.Side.ENEMY):
		assert_int(foe.hp).is_equal(24)
	assert_int(cog.energy_spent_milli).is_equal(6 * Combatant.MILLI)


func test_enemy_intents_count_a_bots_guard() -> void:
	var squad: Array[SquadMemberSummary] = [_member("anvil", H.stats(60, 5, 0, 10, 10), [["Brace", "guard_self"]])]
	var fight := _fight(squad, H.stats(200, 20, 0, 5, 0))
	var planner := IntentPlanner.new()
	assert_int(planner.plan(fight, fight.combatant("foe#1")).amount).is_equal(20)
	fight.advance()
	fight.submit(FightAction.use("brace", "anvil"))
	assert_int(planner.plan(fight, fight.combatant("foe#1")).amount).is_equal(10)


func test_the_preview_shows_a_guard_and_a_heal() -> void:
	var squad: Array[SquadMemberSummary] = [
		_member("spark", H.stats(30, 8, 0, 20, 12), [["Patch Up", "heal_single"], ["Shield Ally", "guard_ally"]]),
		_member("bolt", H.stats(60, 5, 0, 1, 10), [["Strike", "damage_single"]]),
	]
	squad[1].hp = 40
	var fight := _fight(squad, H.stats(200, 20, 0, 10, 0))
	fight.advance()
	var preview := FightPreview.new()
	var guard := preview.preview_choice(fight, FightAction.use("shield", "bolt"))
	assert_str(guard.problem).is_empty()
	assert_dict(guard.guard_changes).is_equal({"bolt": 40})
	var heal := preview.preview_choice(fight, FightAction.use("patch_up", "bolt"))
	assert_int(heal.effect_on("bolt").hp_after.value).is_equal(48)
	# Nothing changed in the real fight.
	assert_int(fight.combatant("bolt").hp).is_equal(40)
	assert_int(fight.combatant("bolt").guard_percent).is_equal(0)


func test_a_fight_with_bot_skills_replays_exactly() -> void:
	var squad := BotFactory.new(BotTuning.load_default()).build_squad(5)
	var summaries: Array[SquadMemberSummary] = []
	for bot in squad.get_fielded():
		summaries.append(bot.to_summary())
	var request := FightRequest.new(FightRequest.Kind.ATTACK, "t", 2, summaries)
	var a := HeadlessFightRunner.run(request, 9, RandomFightPolicy.new(), IntentFightPolicy.new())
	var b := HeadlessFightRunner.run(request, 9, RandomFightPolicy.new(), IntentFightPolicy.new())
	assert_str(a.log_text()).is_equal(b.log_text())


func test_post_fight_counts_patch_up_toward_the_bots_patch_up() -> void:
	var skills: Array[Skill] = [Skill.new("Patch Up", "heal_single", 3, 1)]
	var medic := Bot.new("medic", "Medic", H.stats(30, 2, 2, 9, 30), Personality.new(3), skills)
	var tank := Bot.new("tank", "Tank", H.stats(80, 5, 2, 1, 10), Personality.new(3))
	tank.hp = 30
	var squad: Array[SquadMemberSummary] = [medic.to_summary(), tank.to_summary()]
	var fight := _fight(squad, H.stats(1000, 1, 0, 1, 0))
	var tuning := PostFightTuning.load_default()
	for i in tuning.uses_per_level:
		assert_bool(_until(fight, "medic")).is_true()
		assert_str(fight.submit(FightAction.use("patch_up", "tank"))).is_empty()
	# End the fight: the action limit counts as defeat, which still trains.
	var actor := fight.advance()
	while actor != null:
		assert_str(fight.submit(FightAction.use("strike", fight.opponents_of(actor)[0].id))).is_empty()
		actor = fight.advance()
	var bots: Array[Bot] = [medic, tank]
	var report := PostFight.apply(fight, bots, SkillUseLedger.new(), tuning)
	var change: SkillChange = report.bot("medic").skill_changes.filter(
		func(c: SkillChange) -> bool: return c.combat_skill_id == "patch_up")[0]
	assert_str(change.skill_name).is_equal("Patch Up")
	assert_int(change.uses).is_equal(tuning.uses_per_level)
	assert_int(change.levels_gained()).is_equal(tuning.levels_per_step)
	assert_int(medic.skills[0].level).is_equal(1 + tuning.levels_per_step)


func test_post_fight_maps_each_combat_skill_back_to_the_same_bot_effect() -> void:
	var combat := _tuning()
	var post := PostFightTuning.load_default()
	for effect_id in combat.bot_skill_effects:
		assert_str(post.combat_skill_effects.get(combat.bot_skill_effects[effect_id], "")).is_equal(effect_id)


func test_the_tuning_is_valid() -> void:
	assert_array(_tuning().validate()).is_empty()
