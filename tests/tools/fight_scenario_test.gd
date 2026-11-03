extends GdUnitTestSuite

const H := preload("res://tests/tools/tools_test_helpers.gd")


func _resolve(s: FightScenario) -> ResolvedScenario:
	return s.resolve(H.bot_tuning(), H.enemy_table(), H.combat_tuning())


## `d` as JSON reads it back, so ints and floats compare alike.
func _as_json(d: Dictionary) -> Variant:
	return JSON.parse_string(JSON.stringify(d))


func test_a_scenario_round_trips_through_a_file() -> void:
	var s := H.scenario("random")
	s.kind = FightRequest.Kind.DEFEND
	s.enemy_entries = ["hound", {"enemy": "drone", "count": 2}]
	var path := create_temp_dir("scenario").path_join("x.json")
	assert_int(ScenarioFiles.save_scenario(s, path)).is_equal(OK)
	var loaded := ScenarioFiles.load_scenario(path)
	assert_that(_as_json(loaded.to_dict())).is_equal(_as_json(s.to_dict()))
	assert_int(loaded.defense_level).is_equal(1)
	assert_int(loaded.kind).is_equal(FightRequest.Kind.DEFEND)
	assert_str(loaded.player_policy).is_equal("random")


func test_inline_bots_become_the_squad() -> void:
	var r := _resolve(H.scenario())
	assert_array(r.problems).is_empty()
	assert_int(r.request.squad.size()).is_equal(2)
	assert_str(r.request.squad[0].id).is_equal("left")
	assert_int(r.request.squad[1].stats.speed).is_equal(8)
	assert_int(r.request.defense_level).is_equal(1)


func test_saved_squad_files_supply_bots() -> void:
	var tuning := H.bot_tuning()
	var dir := create_temp_dir("scenario_bots")
	var bot := BotLibrary.new_bot(tuning, "saved", "Saved")
	bot.stats.attack = 33
	assert_int(BotLibrary.save_bot(bot, dir, tuning)).is_equal(OK)
	var draft := BotFactory.new(tuning).build_squad(5)
	var draft_path := dir.path_join("draft.tres")
	assert_int(BotSquadStorage.save_squad(draft, draft_path)).is_equal(OK)
	var s := FightScenario.from_dict({"name": "files", "defense_level": 0, "squad": [
		{"squad_file": BotLibrary.path_for(dir, "saved")},
		{"squad_file": draft_path, "bot_id": draft.bots[3].id},
	]})
	var r := _resolve(s)
	assert_array(r.problems).is_empty()
	assert_int(r.request.squad[0].stats.attack).is_equal(33)
	assert_str(r.request.squad[1].id).is_equal(draft.bots[3].id)


func test_a_draft_seed_fields_that_drafts_squad() -> void:
	var r := _resolve(FightScenario.from_dict({"name": "draft", "squad": [{"draft_seed": 77}]}))
	var expected := BotFactory.new(H.bot_tuning()).build_squad(77).get_fielded()
	assert_array(r.request.squad.map(func(m: SquadMemberSummary) -> String: return m.id)) \
		.is_equal(expected.map(func(b: Bot) -> String: return b.id))


func test_explicit_enemies_appear_every_fight_in_order() -> void:
	var s := H.scenario()
	s.enemy_entries = ["hound", {"enemy": "drone", "count": 2}, H.inline_bot("boss", 40, 9, 5, 3)]
	var r := _resolve(s)
	assert_array(r.problems).is_empty()
	for seed_value in [1, 2, 3]:
		var fight := r.start(seed_value).fight
		var enemy_ids := fight.living(Combatant.Side.ENEMY).map(func(c: Combatant) -> String: return c.id)
		assert_array(enemy_ids).is_equal(["hound#1", "drone#1", "drone#2", "custom_boss#1"])
	var boss := r.start(1).fight.combatant("custom_boss#1")
	assert_int(boss.hp).is_equal(40)
	# Alone of its kind: no number. Two drones: numbered.
	assert_str(boss.display_name).is_equal("Boss")
	assert_str(r.start(1).fight.combatant("drone#2").display_name).ends_with(" 2")
	assert_str(r.start(1).fight.combatant("hound#1").display_name).not_contains("1")
	# Rewards still follow the defense level.
	assert_that(r.enemy_table.rewards(1)).is_equal(H.enemy_table().rewards(1))


func test_without_enemies_they_are_drawn_from_the_table() -> void:
	var r := _resolve(H.scenario())
	assert_object(r.enemy_table).is_not_instanceof(FixedEnemyTable)
	assert_int(r.start(1).fight.living(Combatant.Side.ENEMY).size()).is_equal(2)


func test_problems_are_reported() -> void:
	var s := FightScenario.from_dict({
		"name": "", "defense_level": 9,
		"squad": [{"squad_file": "user://nope.tres"}, {"bot": {"id": "x", "name": "X"}}, {"bot": {
			"id": "y", "name": "Y", "stats": {"hp": 5, "attack": 1, "defense": 1, "speed": 1, "elasticity": 1, "battery_capacity": 1},
			"skills": ["Laser"]}}],
		"enemies": ["dragon"],
		"player_policy": "clever",
	})
	var problems := _resolve(s).problems
	assert_array(problems).contains([
		"scenario has no name", "defense level 9 is outside 0 to 5", "cannot load squad file user://nope.tres",
		"inline bot 'x' has no stats object", "inline bot 'y' has unknown skill 'Laser'", "scenario fields no squad",
		"unknown enemy 'dragon'", "unknown policy 'clever' (use simple, random, intent, patient, careful, greedy, smart)"])


func test_the_intent_policy_plays_enemies_by_their_intents() -> void:
	var s := H.scenario()
	s.enemy_policy = "intent"
	var r := _resolve(s)
	assert_array(r.problems).is_empty()
	assert_object(r.enemy_policy).is_instanceof(IntentFightPolicy)
	assert_bool(r.start(1).run_to_end().fight.is_over()).is_true()


func test_duplicate_squad_ids_are_a_problem() -> void:
	var s := H.scenario()
	s.squad_entries.append(H.inline_bot("left", 10, 1, 1, 1))
	assert_array(_resolve(s).problems).contains(["squad holds bot id 'left' twice"])


func test_the_sample_scenarios_are_playable_with_the_real_data() -> void:
	var paths := ScenarioFiles.list(["res://data/scenarios"])
	assert_int(paths.size()).is_greater_equal(2)
	for path in paths:
		var s := ScenarioFiles.load_scenario(path)
		assert_object(s).override_failure_message("cannot read " + path).is_not_null()
		var r := s.resolve()
		assert_array(r.problems).override_failure_message("%s: %s" % [path, r.problems]).is_empty()
		assert_bool(r.start(1).run_to_end().fight.is_over()).is_true()


func test_settings_files_are_not_listed_as_scenarios() -> void:
	for path in ScenarioFiles.list(["res://data/scenarios"]):
		assert_bool(path.get_file().begins_with("_")).is_false()


func test_inline_bots_round_trip_through_bot_json() -> void:
	var tuning := H.bot_tuning()
	var bot := BotLibrary.new_bot(tuning, "j", "Jay")
	bot.stats.speed = 17
	bot.hp = 1
	bot.skills[1].level = 4
	var problems: Array[String] = []
	var back := BotJson.from_dict(BotJson.to_dict(bot), tuning, problems)
	assert_array(problems).is_empty()
	assert_that(BotJson.to_dict(back)).is_equal(BotJson.to_dict(bot))


func test_a_kit_replaces_every_members_skills_and_leaves_the_tuning_alone() -> void:
	var d := H.scenario().to_dict()
	d["kit"] = ["strike", "heavy_strike"]
	var s := FightScenario.from_dict(d)
	var tuning := H.combat_tuning()
	var before := tuning.player_skills.duplicate()
	var r := s.resolve(H.bot_tuning(), H.enemy_table(), tuning)
	assert_array(r.problems).is_empty()
	assert_array(tuning.player_skills).is_equal(before)
	assert_array(r.tuning.player_skills).is_equal(["strike", "heavy_strike"])
	var fight := r.start(1).fight
	for member in r.request.squad:
		assert_array(member.skills).is_empty()
		assert_array(fight.combatant(member.id).skill_ids).is_equal(["strike", "heavy_strike"])
	assert_array(s.to_dict().kit).is_equal(["strike", "heavy_strike"])


func test_a_kit_naming_an_unknown_action_is_a_problem() -> void:
	var d := H.scenario().to_dict()
	d["kit"] = ["strike", "nope"]
	assert_str(", ".join(_resolve(FightScenario.from_dict(d)).problems)).contains("nope")


func test_no_kit_is_left_out_of_the_file() -> void:
	assert_bool(H.scenario().to_dict().has("kit")).is_false()


func test_an_opening_gauge_spread_round_trips_and_goes_on_a_copy_of_the_tuning() -> void:
	var d := H.scenario().to_dict()
	assert_bool(d.has("opening_gauge_spread_percent")).is_false()
	d["opening_gauge_spread_percent"] = 40
	var s := FightScenario.from_dict(d)
	assert_int(s.to_dict().opening_gauge_spread_percent).is_equal(40)
	var tuning := H.combat_tuning()
	var r := s.resolve(H.bot_tuning(), H.enemy_table(), tuning)
	assert_array(r.problems).is_empty()
	assert_int(tuning.opening_gauge_spread_percent).is_equal(0)
	assert_int(r.tuning.opening_gauge_spread_percent).is_equal(40)


func test_an_opening_gauge_spread_outside_0_to_99_is_a_problem() -> void:
	var d := H.scenario().to_dict()
	d["opening_gauge_spread_percent"] = 100
	assert_str(", ".join(_resolve(FightScenario.from_dict(d)).problems)).contains("opening_gauge_spread_percent")


## The deep dive's sandbox (S9): three bots with Basic, Shred, Heavy Shot,
## Brace (and Wait) against a Charger, a Plated and a Scaler.
func test_the_sandbox_is_the_deep_dives_test_fight() -> void:
	var scenario := ScenarioFiles.load_scenario("res://data/scenarios/sandbox_3v3.json")
	var resolved := scenario.resolve()
	assert_array(resolved.problems).is_empty()
	assert_int(scenario.opening_gauge_spread_percent).is_greater(0)
	for seed_value in [1, 2, 3]:
		var fight := resolved.start(seed_value).fight
		var squad := fight.combatants.filter(func(c: Combatant) -> bool: return c.side == Combatant.Side.PLAYER)
		var enemies := fight.combatants.filter(func(c: Combatant) -> bool: return c.side == Combatant.Side.ENEMY)
		assert_int(squad.size()).is_equal(3)
		for c: Combatant in squad:
			assert_array(c.skill_ids).is_equal(["strike", "shred", "heavy_strike", "brace"])
		assert_array(enemies.map(func(c: Combatant) -> String: return c.archetype.id)).is_equal(
			["charger", "plated", "scaler"])


## Fixed enemies, yet each seed opens differently (questions row 67), and the
## same seed opens the same way.
func test_the_sandbox_opening_varies_by_seed_and_repeats_for_a_seed() -> void:
	var resolved := ScenarioFiles.load_scenario("res://data/scenarios/sandbox_3v3.json").resolve()
	var openings := {}
	for seed_value in range(1, 11):
		var gauges: Array = resolved.start(seed_value).fight.combatants.map(func(c: Combatant) -> int: return c.gauge)
		assert_array(resolved.start(seed_value).fight.combatants.map(func(c: Combatant) -> int: return c.gauge)).is_equal(gauges)
		openings[str(gauges)] = true
	assert_int(openings.size()).is_greater(8)
	var greedy := {}
	resolved.player_policy = GreedyFightPolicy.new()
	for seed_value in range(1, 11):
		greedy["\n".join(FightLog.lines(resolved.start(seed_value).run_to_end().fight.events))] = true
	assert_int(greedy.size()).is_greater(1)
