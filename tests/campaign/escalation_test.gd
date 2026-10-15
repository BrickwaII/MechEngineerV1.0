extends GdUnitTestSuite
## Escalation: alert tiers at 1/3 and 2/3 of the map held, no drop, enemy
## levels by tier, fortifying while left alone, saves and the off variant. On
## the 12-region Lake Washington map, so the tiers need 4 and 8 held.

const MAP := "res://data/regions/lake_washington_12.json"
const TUNING := "res://data/tuning/act1.json"


class Recorder:
	extends FightService
	var requests: Array[FightRequest] = []
	var outcome := FightResult.Outcome.VICTORY

	func start_fight(request: FightRequest) -> void:
		requests.append(request)
		var result := FightResult.new(outcome, 0.0, {})
		Engine.get_main_loop().process_frame.connect(func() -> void: finished.emit(result), CONNECT_ONE_SHOT)


var _map: RegionMap
var _cards: Array[Dictionary] = []


func before_test() -> void:
	_map = RegionMap.load_file(MAP)
	_cards = []


func _campaign(option := CampaignVariants.ESCALATION_ON, service: FightService = null) -> Campaign:
	var v := CampaignVariants.defaults()
	v.choose(CampaignVariants.ESCALATION, option)
	var tuning := MapTuning.load_file(TUNING)
	var state := Campaign.new_run_state(_map, tuning, null, v)
	# Hold only the first region, so _hold() counts exactly.
	state.owned = PackedStringArray([_map.ids()[0]])
	var c := Campaign.new(_map, tuning, StubSquadProvider.new(),
		service if service != null else StubFightService.new(), state)
	c.escalated.connect(func(card: Dictionary) -> void: _cards.append(card))
	return c


## Holds the first `count` regions in file order, as captures would.
func _hold(c: Campaign, count: int) -> void:
	for region_id in _map.ids().slice(0, count):
		if not c.is_owned(region_id):
			c._set_owned(region_id, true)


func _hostile(c: Campaign) -> MapRegion:
	for region in _map.regions:
		if not c.is_owned(region.id):
			return region
	return null


func test_the_data_file_has_three_named_tiers_per_act() -> void:
	var data := Escalation.load_data()
	assert_int((data.acts as Array).size()).is_equal(3)
	for act: Dictionary in data.acts:
		assert_int((act.tiers as Array).size()).is_equal(3)
		for tier: Dictionary in act.tiers:
			assert_str(str(tier.name)).is_not_empty()
	assert_str(str(data.acts[0].tiers[0].name)).is_equal("Unnoticed")
	assert_str(str(data.acts[0].tiers[1].name)).is_equal("Local Concern")
	assert_str(str(data.acts[0].tiers[2].name)).is_equal("Major Crisis")


func test_tiers_rise_at_one_third_and_two_thirds_held() -> void:
	var c := _campaign()
	var e := c.escalation
	assert_int(e.needed_for(1)).is_equal(4)
	assert_int(e.needed_for(2)).is_equal(8)
	assert_int(e.needed_for(3)).is_equal(-1)
	_hold(c, 3)
	assert_int(e.tier()).is_equal(0)
	_hold(c, 4)
	assert_int(e.tier()).is_equal(1)
	assert_str(e.tier_name()).is_equal("Local Concern")
	_hold(c, 7)
	assert_int(e.tier()).is_equal(1)
	_hold(c, 8)
	assert_int(e.tier()).is_equal(2)
	assert_int(e.to_next()).is_equal(-1)
	assert_float(e.progress()).is_equal(1.0)


func test_each_tier_gained_brings_a_news_card() -> void:
	var c := _campaign()
	_hold(c, 4)
	assert_int(_cards.size()).is_equal(1)
	assert_str(str(_cards[0].kind)).is_equal(Escalation.NEWS_TIER)
	assert_int(int(_cards[0].tier)).is_equal(1)
	assert_str(str(_cards[0].headline)).is_not_empty()
	assert_str(str(_cards[0].body)).contains("Local Concern")
	assert_bool(str(_cards[0].body).contains("{")).is_false()
	_hold(c, 8)
	assert_int(_cards.size()).is_equal(2)
	assert_int(int(_cards[1].tier)).is_equal(2)


func test_progress_counts_toward_the_next_tier() -> void:
	var c := _campaign()
	_hold(c, 2)
	assert_float(c.escalation.progress()).is_equal_approx(0.5, 0.0001)
	assert_int(c.escalation.to_next()).is_equal(2)
	_hold(c, 6)
	assert_float(c.escalation.progress()).is_equal_approx(0.5, 0.0001)
	assert_int(c.escalation.to_next()).is_equal(2)


func test_tiers_never_drop_when_ground_is_lost() -> void:
	var c := _campaign()
	_hold(c, 8)
	for region_id in _map.ids().slice(0, 6):
		c._set_owned(region_id, false)
	assert_int(c.escalation.tier()).is_equal(2)
	var lost := _map.get_region(_map.ids()[0])
	# Lost ground fights at the raised tier like any hostile region.
	assert_int(c.defense_of(lost.id)).is_equal(c.escalation.band_level(lost.defense, 2))


func test_enemy_levels_follow_the_alert_tier() -> void:
	var c := _campaign()
	var e := c.escalation
	for defense in range(0, MapRegion.MAX_DEFENSE + 1):
		var calm := e.band_level(defense, 0)
		var concern := e.band_level(defense, 1)
		var crisis := e.band_level(defense, 2)
		assert_bool(calm <= concern and concern <= crisis).is_true()
		assert_int(calm).is_between(0, 2)
		assert_int(crisis).is_between(3, 5)
	var region := _hostile(c)
	var before := c.defense_of(region.id)
	_hold(c, 8)
	assert_int(c.defense_of(_hostile(c).id)).is_equal(e.band_level(_hostile(c).defense, 2))
	assert_int(e.band_level(region.defense, 2)).is_greater(before)


func test_the_static_mapping_matches_the_live_one() -> void:
	var c := _campaign()
	_hold(c, 4)
	for i in 6:
		c.escalation.advance_day()
	for region in _map.regions:
		if not c.is_owned(region.id):
			assert_int(Escalation.level_for(0, region.defense, c.escalation.tier(), c.escalation.fortify_of(region.id))) \
				.is_equal(c.defense_of(region.id))


func test_act_one_alert_tiers_map_to_rising_enemy_unit_tiers() -> void:
	# The faction tables turn levels into unit tiers: Unnoticed fields only
	# beginners, Major Crisis none.
	var factions := FactionTable.load_default()
	var c := _campaign()
	for region in _map.regions:
		assert_str(factions.tier_for("act1", c.escalation.band_level(region.defense, 0))).is_equal("beginner")
		assert_str(factions.tier_for("act1", c.escalation.band_level(region.defense, 2))).is_not_equal("beginner")


func test_attacks_are_fought_at_the_escalated_level() -> void:
	var service := Recorder.new()
	var c := _campaign(CampaignVariants.ESCALATION_ON, service)
	_hold(c, 8)
	var target := ""
	for region in _map.regions:
		if c.standing(region.id) == Campaign.Standing.IN_RANGE:
			target = region.id
			break
	assert_bool(await c.attack(target)).is_true()
	assert_int(service.requests[0].defense_level).is_equal(c.escalation.band_level(_map.get_region(target).defense, 2))


func test_hostile_regions_fortify_while_left_alone_on_alert() -> void:
	var c := _campaign()
	var data: Dictionary = Escalation.load_data().fortify
	var per_level := int(data.days_per_level)
	var max_levels := int(data.max_levels)
	var region := _hostile(c)
	# Not on alert yet: nothing fortifies.
	for i in per_level:
		c.escalation.advance_day()
	assert_int(c.escalation.fortify_of(region.id)).is_equal(0)
	_hold(c, 4)
	region = _hostile(c)
	var level := c.defense_of(region.id)
	for i in per_level - 1:
		c.escalation.advance_day()
	assert_int(c.escalation.fortify_of(region.id)).is_equal(0)
	c.escalation.advance_day()
	assert_int(c.escalation.fortify_of(region.id)).is_equal(1)
	assert_int(c.defense_of(region.id)).is_equal(mini(level + 1, FightRequest.MAX_DEFENSE_LEVEL))
	for i in per_level * (max_levels + 2):
		c.escalation.advance_day()
	assert_int(c.escalation.fortify_of(region.id)).is_equal(max_levels)
	assert_bool(_cards.any(func(card: Dictionary) -> bool:
		return card.kind == Escalation.NEWS_FORTIFIED and region.id in card.regions)).is_true()


func test_days_pass_fortify_through_campaign_time() -> void:
	var c := _campaign()
	_hold(c, 4)
	var region := _hostile(c)
	var per_level := int(Escalation.load_data().fortify.days_per_level)
	c.state.time_points = 0
	c._advance(per_level * c.tuning.points_per_day)
	assert_int(c.escalation.fortify_of(region.id)).is_equal(1)


func test_an_attack_restarts_the_count_and_a_capture_clears_fortification() -> void:
	var c := _campaign()
	_hold(c, 4)
	var region := _hostile(c)
	var per_level := int(Escalation.load_data().fortify.days_per_level)
	for i in per_level - 1:
		c.escalation.advance_day()
	c.escalation.note_attack(region.id)
	c.escalation.advance_day()
	assert_int(c.escalation.fortify_of(region.id)).is_equal(0)
	for i in per_level:
		c.escalation.advance_day()
	assert_int(c.escalation.fortify_of(region.id)).is_equal(1)
	c._set_owned(region.id, true)
	assert_int(c.escalation.fortify_of(region.id)).is_equal(0)
	c._set_owned(region.id, false)
	assert_int(c.escalation.fortify_of(region.id)).is_equal(0)


func test_off_fights_at_the_region_defense_and_never_fortifies() -> void:
	var c := _campaign(CampaignVariants.ESCALATION_OFF)
	_hold(c, 8)
	assert_int(c.escalation.tier()).is_equal(0)
	for i in 30:
		c.escalation.advance_day()
	for region in _map.regions:
		assert_int(c.defense_of(region.id)).is_equal(region.defense)
	assert_array(_cards).is_empty()


func test_quarters_variant_rises_sooner() -> void:
	var c := _campaign(CampaignVariants.ESCALATION_QUARTERS)
	assert_int(c.escalation.needed_for(1)).is_equal(3)
	assert_int(c.escalation.needed_for(2)).is_equal(6)


func test_escalation_is_saved_and_loaded_exactly() -> void:
	var c := _campaign()
	_hold(c, 4)
	for i in 7:
		c.escalation.advance_day()
	var loaded := RunState.from_dict(c.state.to_dict())
	assert_dict(loaded.escalation).is_equal(c.state.escalation)
	var again := Campaign.new(_map, c.tuning, StubSquadProvider.new(), StubFightService.new(), loaded)
	assert_int(again.escalation.tier()).is_equal(1)
	for region in _map.regions:
		assert_int(again.defense_of(region.id)).is_equal(c.defense_of(region.id))


func test_a_run_from_before_escalation_plays_without_it() -> void:
	var v := CampaignVariants.for_run({"auto-expansion": "off"})
	assert_str(v.option(CampaignVariants.ESCALATION)).is_equal(CampaignVariants.ESCALATION_OFF)
	assert_str(CampaignVariants.defaults().option(CampaignVariants.ESCALATION)).is_equal(CampaignVariants.ESCALATION_ON)


func test_each_act_starts_unnoticed() -> void:
	var c := _campaign()
	_hold(c, 8)
	var next := RunState.new()
	next.act = 1
	assert_dict(next.escalation).is_empty()
	next.owned = PackedStringArray([_map.ids()[0]])
	next.variants = c.state.variants.duplicate()
	var e := Escalation.new(_map, next, CampaignVariants.for_run(next.variants))
	assert_int(e.tier()).is_equal(0)
	assert_str(e.tier_name()).is_equal("Off the Radar")


func test_the_headline_turns_over_every_points_per_headline_time_points() -> void:
	var data := Escalation.load_data().duplicate(true)
	var lines := ["a", "b", "c"]
	var state := RunState.new()
	var e := Escalation.new(_map, state, null, data)
	assert_int(int((data.news as Dictionary).get("points_per_headline", 0))).is_equal(4)
	var picked: Array[String] = []
	for points in [0, 3, 4, 8]:
		state.time_points = points
		picked.append(e._pick(lines))
	assert_array(picked).is_equal(["a", "a", "b", "c"])
	data.news.points_per_headline = 2
	state.time_points = 3
	assert_str(Escalation.new(_map, state, null, data)._pick(lines)).is_equal("b")
