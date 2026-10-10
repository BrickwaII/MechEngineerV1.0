extends GdUnitTestSuite
## The run flow, headless: draft -> map -> fight -> post-fight -> map with real
## bots, driven through the same calls the screens' input handlers make, and
## the run save with bots. Fights play on the real battle screen unless a test
## asks for auto-fights.

const SCENE := preload("res://ui/run/run_flow.tscn")
const Helpers := preload("res://tests/ui/fight/fight_ui_helpers.gd")
const SAVE_PATH := "user://run_flow_test.tres"
## Bots fight with their own drafted skills, so the seed must draft a squad
## that wins its first fight. 13 does under both draft rules.
const RUN_SEED := 13

var _runner: GdUnitSceneRunner
var _flow: RunFlow


func _open(auto_fights := false, choose_start := false) -> void:
	_flow = SCENE.instantiate()
	_flow.run_seed = RUN_SEED
	_flow.auto_fights = auto_fights
	_flow.choose_start = choose_start
	_flow.fight_screen_tuning = Helpers.fast_tuning()
	_runner = scene_runner(auto_free(_flow))
	await _runner.simulate_frames(2)


func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Picks the first squad_size bots of the draft, as clicking their cards does,
## and deploys them.
func _draft() -> void:
	var screen := _flow.draft_screen
	for i in screen.picker.squad_size():
		screen.cards[screen.picker.bots()[i].id].pressed.emit()
	screen.start_button.pressed.emit()
	await _frames(1)


## The weakest hostile region next to the network.
func _adjacent_target() -> String:
	var campaign: Campaign = _flow.overworld.campaign
	var best: MapRegion = null
	for region in campaign.map.regions:
		if campaign.standing(region.id) == Campaign.Standing.IN_RANGE and (best == null or region.defense < best.defense):
			best = region
	return best.id


## Plays the battle screen to its end, each bot turn by mouse.
func _play_battle(screen: BattleScreen) -> void:
	var fight := screen.fight
	var guard := 0
	while not fight.is_over() and guard < 2000:
		if screen.handler.is_player_turn():
			Helpers.play_support_turn_by_mouse(screen)
		else:
			await _frames(1)
		guard += 1


func _await_stage(stage: RunFlow.Stage) -> void:
	var guard := 0
	while _flow.stage != stage and guard < 30:
		await _frames(1)
		guard += 1


func _personalities() -> Dictionary:
	var out := {}
	for bot in _flow.squad.get_fielded():
		out[bot.id] = PersonalityDrift.values_of(bot.personality)
	return out


func test_a_new_run_opens_the_seeded_draft() -> void:
	await _open()
	assert_int(_flow.stage).is_equal(RunFlow.Stage.DRAFT)
	assert_int(_flow.draft_screen.draft_seed).is_equal(RUN_SEED)
	assert_str(_flow.draft_screen.start_button.text).is_equal("DEPLOY SQUAD")
	assert_object(_flow.overworld).is_null()


func test_the_drafted_bots_reach_the_map_through_real_contracts() -> void:
	await _open()
	await _draft()
	assert_int(_flow.stage).is_equal(RunFlow.Stage.MAP)
	assert_object(_flow.draft_screen).is_null()
	var overworld: Control = _flow.overworld
	assert_object(overworld.squad_provider).is_instanceof(BotSquadProvider)
	assert_object(overworld.fight_service).is_instanceof(RunFightService)
	assert_object(overworld.campaign.squad_provider).is_same(overworld.squad_provider)
	var ids: Array = overworld.campaign.squad_provider.get_squad().map(func(m: SquadMemberSummary) -> String: return m.id)
	assert_array(ids).is_equal(Array(_flow.squad.fielded_ids))
	# No start choice in normal play: the run seed picks one of act 1's starts.
	assert_bool(overworld._modal.visible).is_false()
	var options: Array = overworld.campaign.map.start_options()
	assert_int(options.size()).is_greater(1)
	assert_str(overworld.campaign.state.start_id).is_equal(options[posmod(RUN_SEED, options.size())].id)
	assert_str(_flow.seeded_start(options)).is_equal(overworld.campaign.state.start_id)


func test_the_seeded_start_follows_the_seed() -> void:
	await _open()
	var options: Array = RegionMap.load_file("res://data/regions/seattle.json").start_options()
	var picked := {}
	for seed_value in range(options.size()):
		_flow.current_seed = seed_value
		picked[_flow.seeded_start(options)] = true
	# Every start is reachable, and the same seed always gives the same one.
	assert_int(picked.size()).is_equal(options.size())
	_flow.current_seed = -7
	assert_str(_flow.seeded_start(options)).is_equal(_flow.seeded_start(options))


func test_the_start_choice_is_a_dev_option() -> void:
	await _open(false, true)
	await _draft()
	var overworld: Control = _flow.overworld
	assert_bool(overworld._modal.visible).is_true()
	var options: Array = overworld.campaign.map.start_options()
	overworld.choose_start(options[-1].id)
	assert_str(overworld.campaign.state.start_id).is_equal(options[-1].id)


func test_one_whole_run_map_fight_post_fight_map() -> void:
	await _open()
	await _draft()
	var overworld: Control = _flow.overworld
	var campaign: Campaign = overworld.campaign
	var target := _adjacent_target()
	var grid_before := campaign.state.grid
	var time_before := campaign.state.time_points
	var before := _personalities()

	overworld._on_attack(target)
	await _frames(1)
	assert_int(_flow.stage).is_equal(RunFlow.Stage.FIGHT)
	var screen := _flow.battle_screen
	assert_object(screen).is_not_null()
	assert_bool(overworld.visible).is_false()
	assert_bool(campaign.fighting).is_true()
	# The fight is the drafted squad against the target's defense level.
	assert_str(screen.fight.request.territory_id).is_equal(target)
	assert_int(screen.fight.living(Combatant.Side.PLAYER).size()).is_equal(_flow.squad.fielded_ids.size())
	# The debug overlay is on the screen, hidden until F3.
	assert_object(_flow.debug_overlay.get_parent()).is_same(screen)
	assert_bool(_flow.debug_overlay.visible).is_false()

	var fight := screen.fight
	await _play_battle(screen)
	await _await_stage(RunFlow.Stage.POST_FIGHT)
	assert_int(_flow.stage).is_equal(RunFlow.Stage.POST_FIGHT)
	var won := fight.outcome == FightResult.Outcome.VICTORY
	assert_bool(won).is_true()

	# The result reached the map.
	assert_bool(campaign.fighting).is_false()
	assert_bool(campaign.is_owned(target)).is_equal(won)
	assert_float(campaign.state.grid).is_less(grid_before)
	assert_int(campaign.state.time_points).is_greater(time_before)

	# PostFight was applied to the bots, and the readout shows that report.
	var report := _flow.fight_service.last_report
	assert_str(report.error).is_empty()
	assert_bool(report.is_victory()).is_equal(won)
	assert_object(_flow.readout.report).is_same(report)
	assert_int(report.bots.size()).is_equal(_flow.squad.fielded_ids.size())
	var drifted := false
	for bot in _flow.squad.get_fielded():
		var r := report.bot(bot.id)
		assert_object(r).is_not_null()
		assert_array(r.personality_before).is_equal(before[bot.id])
		assert_array(PersonalityDrift.values_of(bot.personality)).is_equal(r.personality_after)
		drifted = drifted or r.personality_after != r.personality_before
		# TODO(decision: hp-carryover): bots heal to full between fights.
		assert_int(bot.hp).is_equal(bot.get_max_hp())
		# Every skill the bot used trains one of its own skills, except the
		# basic attack a bot keeps without holding Strike.
		for change in r.skill_changes:
			assert_bool(change.has_bot_skill() or change.combat_skill_id == fight.tuning.basic_attack).is_true()
	assert_bool(drifted).is_true()
	# Applied once: the fight is marked.
	assert_str(PostFight.apply(fight, _flow.squad.get_fielded()).error).is_not_empty()

	_flow.continue_button.pressed.emit()
	await _frames(1)
	assert_int(_flow.stage).is_equal(RunFlow.Stage.MAP)
	assert_object(_flow.readout).is_null()
	assert_bool(overworld.visible).is_true()
	assert_str(overworld._modal_eyebrow.text).is_equal("ASSAULT · VICTORY")


func test_a_lost_fight_leaves_the_region_hostile_and_still_trains_the_bots() -> void:
	await _open()
	await _draft()
	var overworld: Control = _flow.overworld
	var campaign: Campaign = overworld.campaign
	var target := _adjacent_target()
	overworld._on_attack(target)
	await _frames(1)
	var screen := _flow.battle_screen
	var fight := screen.fight
	# Scripted choices: every bot only ever waits, so the enemies win.
	var guard := 0
	while not fight.is_over() and guard < 4000:
		if screen.handler.is_player_turn():
			assert_str(screen.send(FightCommand.wait("strike"))).is_empty()
		else:
			await _frames(1)
		guard += 1
	await _await_stage(RunFlow.Stage.POST_FIGHT)
	assert_bool(fight.outcome == FightResult.Outcome.DEFEAT).is_true()
	assert_bool(campaign.is_owned(target)).is_false()
	assert_bool(_flow.fight_service.last_report.is_victory()).is_false()
	assert_int(_flow.fight_service.last_report.bots.size()).is_equal(_flow.squad.fielded_ids.size())
	for bot in _flow.squad.bots:
		assert_int(bot.hp).is_equal(bot.get_max_hp())
	_flow.continue_to_map()
	assert_str(overworld._modal_eyebrow.text).is_equal("ASSAULT · DEFEAT")


func test_auto_fights_run_the_same_flow_headless() -> void:
	await _open(true)
	await _draft()
	var overworld: Control = _flow.overworld
	var target := _adjacent_target()
	await overworld._on_attack(target)
	assert_int(_flow.stage).is_equal(RunFlow.Stage.POST_FIGHT)
	var report := _flow.fight_service.last_report
	assert_bool(overworld.campaign.is_owned(target)).is_equal(report.is_victory())
	_flow.continue_to_map()
	assert_int(_flow.stage).is_equal(RunFlow.Stage.MAP)


func test_f3_shows_the_debug_overlay_on_the_battle_screen() -> void:
	await _open()
	await _draft()
	_flow.overworld._on_attack(_adjacent_target())
	await _frames(1)
	var overlay := _flow.debug_overlay
	var key := InputEventKey.new()
	key.keycode = KEY_F3
	key.pressed = true
	overlay._unhandled_key_input(key)
	assert_bool(overlay.visible).is_true()
	assert_object(overlay.fight).is_same(_flow.battle_screen.fight)
	overlay._unhandled_key_input(key)
	assert_bool(overlay.visible).is_false()
	# Finish the fight, so the map's attack is not left waiting on it.
	await _play_battle(_flow.battle_screen)
	await _await_stage(RunFlow.Stage.POST_FIGHT)


func test_new_run_on_the_map_goes_back_to_the_draft() -> void:
	await _open()
	await _draft()
	_flow.overworld._on_new_run()
	await _frames(1)
	assert_int(_flow.stage).is_equal(RunFlow.Stage.DRAFT)
	assert_object(_flow.overworld).is_null()
	assert_object(_flow.draft_screen).is_not_null()


func test_save_and_load_round_trip_with_bots() -> void:
	await _open(true)
	await _draft()
	var overworld: Control = _flow.overworld
	await overworld._on_attack(_adjacent_target())
	_flow.continue_to_map()
	# Into act 2, so the act is part of what comes back.
	assert_str(overworld.advance_act()).is_empty()
	_flow.ledger.set_banked(_flow.squad.fielded_ids[0], "Strike", 3)
	assert_int(_flow.save_run(SAVE_PATH)).is_equal(OK)

	var state: Dictionary = overworld.campaign.state.to_dict()
	var bots := {}
	for bot in _flow.squad.bots:
		bots[bot.id] = [PersonalityDrift.values_of(bot.personality), bot.skills.map(func(s: Skill) -> int: return s.level), bot.stats.hp]
	var fielded := _flow.squad.fielded_ids.duplicate()
	var banked := _flow.ledger.banked.duplicate()

	# A fresh flow, still on its draft, loads the run.
	await _open(true)
	assert_int(_flow.stage).is_equal(RunFlow.Stage.DRAFT)
	assert_bool(_flow.load_run(SAVE_PATH)).is_true()
	await _frames(1)
	assert_int(_flow.stage).is_equal(RunFlow.Stage.MAP)
	var loaded: Control = _flow.overworld
	assert_int(loaded.campaign.state.act).is_equal(1)
	assert_dict(loaded.campaign.state.to_dict()).is_equal(state)
	assert_array(Array(_flow.squad.fielded_ids)).is_equal(Array(fielded))
	for bot in _flow.squad.bots:
		var was: Array = bots[bot.id]
		assert_array(PersonalityDrift.values_of(bot.personality)).is_equal(was[0])
		assert_array(bot.skills.map(func(s: Skill) -> int: return s.level)).is_equal(was[1])
		assert_int(bot.stats.hp).is_equal(was[2])
	assert_dict(_flow.ledger.banked).is_equal(banked)
	assert_int(_flow.current_seed).is_equal(RUN_SEED)
	# The map fights with the loaded bots.
	assert_object(loaded.campaign.squad_provider).is_instanceof(BotSquadProvider)
	var ids: Array = loaded.campaign.squad_provider.get_squad().map(func(m: SquadMemberSummary) -> String: return m.id)
	assert_array(ids).is_equal(Array(fielded))
	assert_object(_flow.fight_service.squad).is_same(_flow.squad)


func test_loading_over_a_run_in_progress_replaces_it() -> void:
	await _open(true)
	await _draft()
	assert_int(_flow.save_run(SAVE_PATH)).is_equal(OK)
	var saved_owned := Array(_flow.overworld.campaign.state.owned)
	await _flow.overworld._on_attack(_adjacent_target())
	_flow.continue_to_map()
	var service_before := _flow.fight_service
	assert_bool(_flow.load_run(SAVE_PATH)).is_true()
	assert_array(Array(_flow.overworld.campaign.state.owned)).is_equal(saved_owned)
	assert_object(_flow.fight_service).is_not_same(service_before)
	assert_object(_flow.overworld.campaign.fight_service).is_same(_flow.fight_service)


func test_a_missing_save_keeps_the_run() -> void:
	await _open(true)
	await _draft()
	var campaign: Campaign = _flow.overworld.campaign
	assert_bool(_flow.load_run("user://no_such_run.tres")).is_false()
	assert_object(_flow.overworld.campaign).is_same(campaign)
	assert_int(_flow.stage).is_equal(RunFlow.Stage.MAP)


func test_a_fight_in_the_run_levels_up_the_bot_skills_it_used() -> void:
	await _open()
	await _draft()
	var tuning := PostFightTuning.load_default()
	# Bank one use short of a level on every skill of every fielded bot.
	var levels := {}
	for bot in _flow.squad.get_fielded():
		for skill in bot.skills:
			_flow.ledger.set_banked(bot.id, skill.display_name, tuning.uses_per_level - 1)
			levels["%s/%s" % [bot.id, skill.display_name]] = skill.level
	_flow.overworld._on_attack(_adjacent_target())
	await _frames(1)
	var fight := _flow.battle_screen.fight
	await _play_battle(_flow.battle_screen)
	await _await_stage(RunFlow.Stage.POST_FIGHT)
	var report := _flow.fight_service.last_report
	var level_ups := 0
	for bot in _flow.squad.get_fielded():
		var r := report.bot(bot.id)
		for change in r.skill_changes:
			if not change.has_bot_skill():
				continue
			var skill := _skill_named(bot, change.skill_name)
			# One use short of a level was banked, so any use raises it at least once.
			assert_int(change.level_after).is_greater(levels["%s/%s" % [bot.id, skill.display_name]])
			assert_int(skill.level).is_equal(change.level_after)
			level_ups += 1
	assert_int(level_ups).is_greater(0)
	# The readout shows the level-up, not "no skill to train".
	var text := _texts(_flow.readout)
	assert_str(text).contains("LEVEL UP")
	assert_str(text).not_contains("no skill to train")
	assert_bool(fight.is_over()).is_true()


func _skill_named(bot: Bot, skill_name: String) -> Skill:
	for skill in bot.skills:
		if skill.display_name == skill_name:
			return skill
	return null


func _texts(node: Node) -> String:
	var out := PackedStringArray()
	if node is Label:
		out.append((node as Label).text)
	for child in node.get_children():
		out.append(_texts(child))
	return "\n".join(out)
