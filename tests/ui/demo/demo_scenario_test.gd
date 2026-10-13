extends GdUnitTestSuite
## Demo scenarios (data/demo/): every shipped one loads and builds, and the
## loader builds what the file says.


func _scenario(d: Dictionary) -> DemoScenario:
	var base := {"name": "Test", "description": "A test scenario.", "icon": "time", "act": 1, "kind": "map",
		"squad": {"seed": 13}}
	base.merge(d, true)
	return DemoScenario.from_dict(base, "test")


func test_every_shipped_scenario_loads_and_builds() -> void:
	var all := DemoScenario.load_all()
	assert_int(all.size()).is_greater_equal(3)
	for s in all:
		assert_array(s.problems()).override_failure_message("%s: %s" % [s.id, s.problems()]).is_empty()
		assert_str(s.scenario_name).is_not_empty()
		assert_bool(UiIcons.has(s.icon)).is_true()


func test_scenarios_are_sorted_by_act_then_order() -> void:
	var all := DemoScenario.load_all()
	for i in range(1, all.size()):
		var a := all[i - 1]
		var b := all[i]
		assert_bool(a.act < b.act or (a.act == b.act and a.order <= b.order)).is_true()


func test_the_state_holds_what_the_file_says() -> void:
	var s := _scenario({"act": 2, "held": ["texas", "pacific_northwest"], "alert_tier": 2,
		"fortify": {"*": 1, "california": 3}, "resources": {"energy": 31, "material": 17, "grid": 64},
		"day": 21, "losses": 2, "pressure": {"texas": 100}})
	var problems: Array[String] = []
	var state := s.build_state(problems)
	assert_array(problems).is_empty()
	assert_int(state.act).is_equal(1)
	assert_str(state.region_set_id).is_equal("north_america_19")
	# File order, not the scenario's.
	assert_array(Array(state.owned)).is_equal(["pacific_northwest", "texas"])
	assert_float(state.pressure["texas"]).is_equal(100.0)
	assert_float(state.energy).is_equal(31.0)
	assert_float(state.material).is_equal(17.0)
	assert_float(state.grid).is_equal(64.0)
	assert_int(state.losses).is_equal(2)
	assert_int(int(state.escalation.tier)).is_equal(2)
	assert_int(int(state.escalation.fortify["california"])).is_equal(3)
	assert_int(int(state.escalation.fortify["rockies"])).is_equal(1)
	assert_bool(state.escalation.fortify.has("texas")).is_false()
	# Day 21 on the act's clock.
	var tuning := s.act_plan().load_tuning(1)
	assert_int(state.time_points).is_equal(20 * tuning.points_per_day)


func test_hostile_lists_the_regions_not_held() -> void:
	var s := _scenario({"act": 3, "hostile": ["asia", "europe"]})
	var state := s.build_state()
	assert_int(state.owned.size()).is_equal(6)
	assert_bool("asia" in state.owned).is_false()


func test_unknown_regions_and_bad_fields_are_reported() -> void:
	var problems: Array[String] = []
	assert_object(_scenario({"held": ["atlantis"]}).build_state(problems)).is_null()
	assert_str(problems[0]).contains("atlantis")
	assert_array(_scenario({"kind": "dance"}).errors).is_not_empty()
	assert_array(_scenario({"act": 4}).errors).is_not_empty()
	assert_array(_scenario({"icon": "no_such_icon"}).errors).is_not_empty()
	assert_array(_scenario({"kind": "fight", "fight": {"region": "renton", "level": 9}}).errors).is_not_empty()
	assert_array(_scenario({"kind": "fight", "fight": {"region": "nowhere", "level": 2}}).problems()).is_not_empty()
	assert_array(_scenario({"kind": "fight", "fight": {"region": "renton", "level": 2, "enemies": ["nobody"]}}).problems()).is_not_empty()


func test_skill_ranks_raise_every_skill_of_the_seeded_squad() -> void:
	var plain := _scenario({}).build_squad()
	var ranked := _scenario({"squad": {"seed": 13, "skill_ranks": 2}}).build_squad()
	assert_array(ranked.fielded_ids).is_equal(plain.fielded_ids)
	for bot in plain.get_fielded():
		var other := ranked.get_bot(bot.id)
		for i in bot.skills.size():
			if bot.skills[i] != null:
				assert_int(other.skills[i].level).is_equal(bot.skills[i].level + 2)


func test_picks_choose_the_squad_from_the_draft() -> void:
	var s := _scenario({"squad": {"seed": 13, "picks": ["bot_4", "bot_2", "bot_5"]}})
	var problems: Array[String] = []
	var built := s.build_squad(problems)
	assert_array(problems).is_empty()
	assert_array(built.fielded_ids).is_equal(["bot_4", "bot_2", "bot_5"])


func test_a_fight_scenario_builds_its_request_and_fixed_enemies() -> void:
	var s := _scenario({"kind": "fight", "fight": {"region": "bellevue", "level": 3,
		"enemies": ["resistance_tank_advanced", "resistance_soldier_advanced"], "boss": true}})
	assert_array(s.problems()).is_empty()
	var squad := BotSquadProvider.new(s.build_squad()).get_squad()
	var request := s.fight_request(squad)
	assert_str(request.territory_id).is_equal("bellevue")
	assert_int(request.defense_level).is_equal(3)
	assert_bool(request.is_valid()).is_true()
	var table := s.enemy_table()
	assert_object(table).is_instanceof(FixedEnemyTable)
	assert_array((table as FixedEnemyTable).fixed_ids).is_equal(["resistance_tank_advanced", "resistance_soldier_advanced"])
	assert_object(table.factions).is_not_null()
	assert_bool(s.is_boss()).is_true()
	assert_str(s.music()).is_equal("boss")


func test_a_news_card_uses_the_acts_own_headline() -> void:
	var s := _scenario({"alert_tier": 2, "news": {"kind": "tier"}})
	var map := s.act_plan().load_map(0)
	var card := s.news_card(map)
	assert_str(str(card.headline)).is_not_empty()
	assert_int(int(card.tier)).is_equal(2)
	assert_str(str(card.headline)).not_contains("{")
	assert_dict(_scenario({}).news_card(map)).is_empty()


func test_the_shipped_set_covers_every_act() -> void:
	var by_act := {1: [], 2: [], 3: []}
	var ids := []
	for s in DemoScenario.load_all():
		by_act[s.act].append(s)
		ids.append(s.id)
	for act in [1, 2, 3]:
		var kinds: Array = by_act[act].map(func(s: DemoScenario) -> String: return s.scenario_name)
		for wanted in ["Map, early", "Map, late", "Fight", "Boss"]:
			assert_array(kinds).override_failure_message("act %d has no '%s'" % [act, wanted]).contains([wanted])
	for wanted in ["act3_globe", "act1_forced_defense", "act1_pre_fight", "act3_run_over", "act2_fast_forward"]:
		assert_array(ids).contains([wanted])


## Winnable but meaningful: the fight the demo plays is won by the simple
## auto-player, and a random one still wins some and loses some.
func test_every_demo_fight_is_winnable_but_not_trivial() -> void:
	for s in DemoScenario.load_all():
		if not s.is_fight():
			continue
		var simple := DemoWinRates.measure(s, 1, "simple")
		assert_bool(simple.shown_seed_won).override_failure_message("%s: the shown fight is lost" % s.id).is_true()
		var random := DemoWinRates.measure(s, 20, "random")
		assert_float(random.rate).override_failure_message("%s: %.0f%% for a random player" % [s.id, random.rate]).is_between(10.0, 95.0)
		if s.is_boss():
			assert_float(simple.hp_left).override_failure_message("%s: %.0f%% hp left" % [s.id, simple.hp_left]).is_less(60.0)
