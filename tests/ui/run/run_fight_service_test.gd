extends GdUnitTestSuite
## RunFightService: plays fights with an inner service and applies PostFight
## to the squad before the map hears the result.

var _squad: BotSquad
var _ledger: SkillUseLedger


func before_test() -> void:
	_squad = BotFactory.new(BotTuning.load_default()).build_squad(3)
	_ledger = SkillUseLedger.new()


func _request() -> FightRequest:
	return FightRequest.new(FightRequest.Kind.ATTACK, "t", 1, BotSquadProvider.new(_squad).get_squad())


func test_is_a_fight_service() -> void:
	assert_object(RunFightService.new(StubFightService.new(), _squad, _ledger)).is_instanceof(FightService)


func test_reports_post_fight_then_passes_the_result_on() -> void:
	var inner := AutoFightService.new()
	var service := RunFightService.new(inner, _squad, _ledger)
	var order: Array[String] = []
	var results: Array[FightResult] = []
	service.fight_reported.connect(func(_r: PostFightReport, _res: FightResult) -> void: order.append("report"))
	service.finished.connect(func(res: FightResult) -> void:
		order.append("finished")
		results.append(res))
	service.start_fight(_request())
	assert_array(order).is_empty()
	await get_tree().process_frame
	assert_array(order).is_equal(["report", "finished"])
	assert_int(results[0].outcome).is_equal(inner.last_fight.result().outcome)
	assert_str(service.last_report.error).is_empty()
	assert_int(service.last_report.bots.size()).is_equal(_squad.fielded_ids.size())


func test_bots_heal_to_full_after_a_fight() -> void:
	# TODO(decision: hp-carryover): the default is a full heal between fights.
	for bot in _squad.bots:
		bot.hp = 1
	var service := RunFightService.new(AutoFightService.new(), _squad, _ledger)
	service.start_fight(_request())
	await get_tree().process_frame
	for bot in _squad.bots:
		assert_int(bot.hp).is_equal(bot.get_max_hp())


func test_a_stub_fight_has_no_report() -> void:
	var service := RunFightService.new(StubFightService.new(), _squad, _ledger)
	var reported := [0]
	var finished := [0]
	service.fight_reported.connect(func(_r: PostFightReport, _res: FightResult) -> void: reported[0] += 1)
	service.finished.connect(func(_res: FightResult) -> void: finished[0] += 1)
	service.start_fight(_request())
	for i in 3:
		await get_tree().process_frame
	assert_int(finished[0]).is_equal(1)
	assert_int(reported[0]).is_equal(0)
	assert_object(service.last_report).is_null()


func _service_with(decision: String, option: String) -> RunFightService:
	var service := RunFightService.new(AutoFightService.new(), _squad, _ledger)
	service.variants_source = func() -> FightVariants:
		var v := FightVariants.defaults()
		v.choose(decision, option)
		return v
	return service


func test_carry_keeps_the_hp_each_bot_ended_with() -> void:
	var service := _service_with(FightVariants.HP_CARRYOVER, FightVariants.HP_CARRY)
	service.start_fight(_request())
	await get_tree().process_frame
	var end_hp := HpCarryover.end_hp_by_id(service.inner.last_fight)
	assert_dict(end_hp).is_not_empty()
	for bot in _squad.bots:
		if end_hp.has(bot.id):
			assert_int(bot.hp).is_equal(maxi(1, end_hp[bot.id]))
		else:
			assert_int(bot.hp).is_equal(bot.get_max_hp())


func test_the_fight_plays_with_the_variants_of_its_start() -> void:
	var service := _service_with(FightVariants.ELASTICITY, FightVariants.ELASTICITY_ENERGY)
	service.start_fight(_request())
	await get_tree().process_frame
	assert_str(service.inner.last_fight.tuning.variants.option(FightVariants.ELASTICITY)).is_equal(FightVariants.ELASTICITY_ENERGY)


func test_drift_off_leaves_personalities_alone() -> void:
	var before := {}
	for bot in _squad.bots:
		before[bot.id] = PersonalityDrift.values_of(bot.personality)
	var service := _service_with(FightVariants.PERSONALITY_MAP, FightVariants.PERSONALITY_OFF)
	service.start_fight(_request())
	await get_tree().process_frame
	for bot in _squad.bots:
		assert_array(PersonalityDrift.values_of(bot.personality)).is_equal(before[bot.id])


func test_under_fight_service_grid_cost_a_lost_attack_comes_back_surcharged() -> void:
	var lost := _LostFight.new()
	var service := RunFightService.new(lost, BotFactory.new(BotTuning.load_default()).build_squad(1), SkillUseLedger.new())
	var v := CampaignVariants.defaults()
	v.choose(CampaignVariants.GRID_COST_OWNER, CampaignVariants.GRID_FIGHT_SERVICE)
	service.campaign_variants_source = func() -> CampaignVariants: return v
	var got: Array[FightResult] = []
	service.finished.connect(func(r: FightResult) -> void: got.append(r))
	var squad: Array[SquadMemberSummary] = [SquadMemberSummary.new("a", "A", 10, 10, "", UnitStats.new(10, 1, 1, 1, 1, 1))]
	service.start_fight(FightRequest.new(FightRequest.Kind.ATTACK, "x", 1, squad))
	lost.finished.emit(FightResult.new(FightResult.Outcome.DEFEAT, 10.0, {}))
	assert_int(got.size()).is_equal(1)
	assert_float(got[0].grid_cost).is_equal(10.0 * v.param_float(CampaignVariants.GRID_COST_OWNER, "defeat_multiplier"))


func test_by_default_the_result_passes_through_unchanged() -> void:
	var lost := _LostFight.new()
	var service := RunFightService.new(lost, BotFactory.new(BotTuning.load_default()).build_squad(1), SkillUseLedger.new())
	service.campaign_variants_source = func() -> CampaignVariants: return CampaignVariants.defaults()
	var got: Array[FightResult] = []
	service.finished.connect(func(r: FightResult) -> void: got.append(r))
	var squad: Array[SquadMemberSummary] = [SquadMemberSummary.new("a", "A", 10, 10, "", UnitStats.new(10, 1, 1, 1, 1, 1))]
	service.start_fight(FightRequest.new(FightRequest.Kind.ATTACK, "x", 1, squad))
	lost.finished.emit(FightResult.new(FightResult.Outcome.DEFEAT, 10.0, {}))
	assert_float(got[0].grid_cost).is_equal(10.0)


## A fight service whose fights end when the test says.
class _LostFight:
	extends FightService

	func start_fight(_request: FightRequest) -> void:
		pass
