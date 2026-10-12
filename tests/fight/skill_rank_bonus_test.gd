extends GdUnitTestSuite
## Named ranks in a fight: the rank sets power and name, and a tier's bonus
## effect resolves deterministically (pierce, weakest bonus, heal guard,
## reflect). TODO(decision: skill-ranks).
const Legacy := preload("res://tests/fight/legacy_switches.gd")

const H := preload("res://tests/fight/fight_test_helpers.gd")
const P := preload("res://tests/fight/post_fight/post_fight_test_helpers.gd")


func _tuning() -> CombatTuning:
	var t := CombatTuning.load_default()
	t.skill_ranks = SkillRanks.from_dict({
		"tiers": [
			{"id": "base", "prefix": "", "steps": 5, "fx_levels": [1, 3]},
			{"id": "mega", "prefix": "Mega", "steps": 5, "fx_levels": [5, 8]},
			{"id": "ultra", "prefix": "Ultra", "steps": 0, "fx_levels": [10, 10]},
		],
		"step_power_percent": 6,
		"tier_power_percent": 25,
		"uses_to_next": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
		"bonuses": {
			"heavy_strike": {"mega": {"pierce_percent": 50}},
			"arc_sweep": {"mega": {"weakest_bonus_percent": 100}},
			"patch_up": {"mega": {"heal_guard_percent": 25}},
			"brace": {"mega": {"reflect_percent": 50}},
		},
	})
	return t


func _member(id: String, s: UnitStats, skills: Array) -> SquadMemberSummary:
	var entries: Array[Dictionary] = []
	for e: Array in skills:
		entries.append(SquadMemberSummary.make_skill(e[0], e[1], e[2]))
	return SquadMemberSummary.new(id, id.capitalize(), s.hp, s.hp, "test", s, entries)


func _fight(squad: Array[SquadMemberSummary], foe: UnitStats, count := 1, tuning: CombatTuning = null) -> Fight:
	var table := H.table({"foe": H.enemy_def("Foe", foe)}, "foe", count)
	return Fight.new(H.request(squad), 1, tuning if tuning != null else _tuning(), table)


func test_ranks_are_the_default_and_name_the_skill() -> void:
	assert_str(FightVariants.defaults().option(FightVariants.SKILL_PROGRESSION)).is_equal(FightVariants.PROGRESSION_RANKS)
	var squad: Array[SquadMemberSummary] = [_member("a", H.stats(30, 10, 0, 5, 10),
		[["Overcharge Shot", "damage_single_heavy", 9]])]
	var c := _fight(squad, H.stats(100, 1, 0, 1, 0)).combatant("a").skill("heavy_strike")
	assert_str(c.display_name).is_equal("Mega Overcharge Shot +2")
	assert_int(c.fx_level).is_equal(6)
	# 150% x (100 + 7 steps x 6 + 25) / 100
	assert_int(c.power_percent).is_equal(250)


func test_flat_levels_keep_todays_rule() -> void:
	var flat := FightVariants.defaults()
	flat.choose(FightVariants.SKILL_PROGRESSION, FightVariants.PROGRESSION_FLAT)
	var squad: Array[SquadMemberSummary] = [_member("a", H.stats(30, 10, 0, 5, 10),
		[["Overcharge Shot", "damage_single_heavy", 9]])]
	var c := _fight(squad, H.stats(100, 1, 0, 1, 0), 1, _tuning().with_variants(flat)).combatant("a").skill("heavy_strike")
	assert_str(c.display_name).is_equal("Overcharge Shot")
	assert_int(c.pierce_percent).is_equal(0)
	assert_int(c.fx_level).is_equal(9)


## Attack 10, Mega heavy strike 232%: 23 raw. Defense 10 x 50% = 5 armor;
## pierce 50% leaves 2.5 of it: (2320 - 250) / 100 = 20, not 18.
func test_pierce_ignores_part_of_the_defense() -> void:
	var tuning := _tuning()
	var attacker := H.stats(30, 10, 0, 5, 10)
	var defender := H.stats(100, 1, 10, 1, 0)
	var mega := tuning.skill_at("heavy_strike", 7)
	var plus5 := tuning.skill_at("heavy_strike", 6)
	assert_int(DamageRules.damage(attacker, defender, mega, tuning)).is_equal(20)
	assert_int(DamageRules.damage(attacker, defender, plus5, tuning)).is_equal(14)


func test_a_mega_sweep_hits_the_weakest_harder() -> void:
	var squad: Array[SquadMemberSummary] = [_member("a", H.stats(30, 10, 0, 50, 20),
		[["Arc Sweep", "damage_all", 7]])]
	var fight := _fight(squad, H.stats(40, 1, 0, 1, 0), 3)
	fight.combatant("foe#2").hp = 30
	var a := fight.advance()
	a.energy_milli = a.max_energy_milli
	assert_str(fight.submit(FightAction.use("arc_sweep", "foe#1"))).is_empty()
	# Arc sweep 60% x 1.55 = 93% of 10 = 9; the weakest takes double: 18.
	assert_int(fight.combatant("foe#1").hp).is_equal(31)
	assert_int(fight.combatant("foe#2").hp).is_equal(12)
	assert_int(fight.combatant("foe#3").hp).is_equal(31)


func test_a_mega_heal_also_guards() -> void:
	var squad: Array[SquadMemberSummary] = [
		_member("medic", H.stats(30, 10, 0, 50, 20), [["Patch Up", "heal_single", 7]]),
		_member("tank", H.stats(60, 5, 0, 1, 10), [["Strike", "damage_single", 1]]),
	]
	var fight := _fight(squad, H.stats(100, 1, 0, 1, 0))
	fight.combatant("tank").hp = 20
	var medic := fight.advance()
	medic.energy_milli = medic.max_energy_milli
	assert_str(fight.submit(FightAction.use("patch_up", "tank"))).is_empty()
	assert_int(fight.combatant("tank").hp).is_equal(35)
	assert_int(fight.combatant("tank").guard_percent).is_equal(25)
	assert_str(fight.log_text()).contains("also guards Tank")


## Brace at Mega blocks 77% and reflects half of what it blocks.
func test_a_mega_guard_reflects_part_of_what_it_blocks() -> void:
	var squad: Array[SquadMemberSummary] = [_member("anvil", H.stats(60, 5, 0, 10, 10), [["Brace", "guard_self", 7]])]
	var fight := _fight(squad, H.stats(200, 20, 0, 10, 0))
	var anvil := fight.advance()
	assert_str(anvil.id).is_equal("anvil")
	assert_str(fight.submit(FightAction.use("brace", "anvil"))).is_empty()
	assert_int(anvil.guard_percent).is_equal(77)
	assert_int(anvil.reflect_percent).is_equal(50)
	var foe := fight.advance()
	fight.submit(FightAction.use("strike", "anvil"))
	# 20 x 23% = 4 taken, 16 blocked, 8 back.
	assert_int(anvil.hp).is_equal(56)
	assert_int(foe.hp).is_equal(192)
	assert_int(anvil.reflect_percent).is_equal(0)
	assert_str(fight.log_text()).contains("reflects 8 damage")


func test_a_ranked_fight_replays_exactly() -> void:
	var squad: Array[SquadMemberSummary] = [
		_member("a", H.stats(40, 9, 3, 7, 12), [["Overcharge Shot", "damage_single_heavy", 7], ["Brace", "guard_self", 13]]),
		_member("b", H.stats(35, 7, 2, 5, 12), [["Arc Sweep", "damage_all", 8], ["Patch Up", "heal_single", 7]]),
	]
	var logs: Array[String] = []
	for i in 2:
		var request := H.request(squad, 2)
		var fight := HeadlessFightRunner.run(request, 9, IntentFightPolicy.new(), IntentFightPolicy.new(), _tuning())
		logs.append(fight.log_text())
	assert_str(logs[0]).is_equal(logs[1])


## These tests' numbers were worked out under the old fight switches.
func before() -> void:
	Legacy.pin()


func after() -> void:
	Legacy.unpin()

