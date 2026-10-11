extends GdUnitTestSuite
## OddsEstimator: auto-fights of the squad against the region's own enemy
## draw give a win rate and a label; deterministic for a run seed and region.

const REGION := "ballard"


func _squad() -> Array[SquadMemberSummary]:
	return StubSquadProvider.new().get_squad()


func _tuning(runs: int) -> OddsTuning:
	return OddsTuning.from_dict({"runs": runs, "bands": [
		{"min_win_percent": 70, "label": "Favored"},
		{"min_win_percent": 40, "label": "Even"},
		{"min_win_percent": 15, "label": "Risky"},
		{"min_win_percent": 0, "label": "Outmatched"}]})


func test_the_shipped_tuning_reads_cleanly() -> void:
	var t := OddsTuning.load_default()
	assert_array(t.errors).is_empty()
	assert_int(t.runs).is_greater(0)
	assert_array(t.bands.map(func(b: Dictionary) -> String: return b["label"])).contains_exactly(
		["Favored", "Even", "Risky", "Outmatched"])


func test_bands_pick_the_first_band_reached() -> void:
	var t := _tuning(4)
	assert_str(t.label_for(100.0)).is_equal("Favored")
	assert_str(t.label_for(70.0)).is_equal("Favored")
	assert_str(t.label_for(69.9)).is_equal("Even")
	assert_str(t.label_for(15.0)).is_equal("Risky")
	assert_str(t.label_for(0.0)).is_equal("Outmatched")
	assert_int(t.band_index("Risky")).is_equal(2)
	assert_int(t.band_index("nope")).is_equal(-1)


func test_bad_tuning_is_reported() -> void:
	var t := OddsTuning.from_dict({"runs": 0, "bands": [
		{"min_win_percent": 10, "label": "A"}, {"min_win_percent": 50, "label": "B"}, {"label": "C"}]})
	assert_array(t.errors).contains(["runs must be at least 1", "bands must be listed best first",
		"bands entries need min_win_percent and label"])


func test_an_estimate_is_the_same_for_the_same_seed_and_region() -> void:
	var a := OddsEstimator.new(_tuning(8)).estimate(_squad(), REGION, 1, 42)
	var b := OddsEstimator.new(_tuning(8)).estimate(_squad(), REGION, 1, 42)
	assert_int(a.runs).is_equal(8)
	assert_int(a.wins).is_equal(b.wins)
	assert_str(a.label).is_equal(b.label)
	assert_str(a.label).is_equal(_tuning(8).label_for(100.0 * a.win_rate()))


func test_the_rate_matches_the_fights_it_plays() -> void:
	var est := OddsEstimator.new(_tuning(6))
	var squad := _squad()
	var e := est.estimate(squad, REGION, 2, 5)
	var wins := 0
	for i in 6:
		var fight := HeadlessFightRunner.run(FightRequest.new(FightRequest.Kind.ATTACK, REGION, 2, squad),
			OddsEstimator.seed_for(5, REGION, 2, i), SimpleFightPolicy.new(), IntentFightPolicy.new(),
			est.combat_tuning, est.enemy_table)
		if fight.outcome == FightResult.Outcome.VICTORY:
			wins += 1
	assert_int(e.wins).is_equal(wins)


func test_harder_regions_never_look_easier() -> void:
	var est := OddsEstimator.new(_tuning(8))
	var easy := est.estimate(_squad(), REGION, 0, 3)
	var hard := est.estimate(_squad(), REGION, 5, 3)
	assert_float(easy.win_rate()).is_greater(hard.win_rate())
	assert_str(easy.label).is_equal("Favored")
	assert_str(hard.label).is_equal("Outmatched")


func test_the_estimate_never_replays_the_real_fights_seed() -> void:
	var request := FightRequest.new(FightRequest.Kind.ATTACK, REGION, 3, _squad())
	var real := AutoFightService.new().seed_for(request)
	for i in OddsTuning.load_default().runs:
		assert_int(OddsEstimator.seed_for(0, REGION, 3, i)).is_not_equal(real)


func test_stepping_a_job_gives_the_same_estimate_and_caches_it() -> void:
	var stepped := OddsEstimator.new(_tuning(5))
	var job := stepped.begin(_squad(), REGION, 1, 9)
	assert_object(stepped.cached(_squad(), REGION, 1, 9)).is_null()
	var steps := 0
	while not job.step(0):
		steps += 1
	# A zero budget still plays one fight per step.
	assert_int(steps).is_equal(4)
	var whole := OddsEstimator.new(_tuning(5)).estimate(_squad(), REGION, 1, 9)
	assert_int(job.result.wins).is_equal(whole.wins)
	assert_object(stepped.cached(_squad(), REGION, 1, 9)).is_same(job.result)
	assert_bool(stepped.begin(_squad(), REGION, 1, 9).done).is_true()


func test_a_changed_squad_is_estimated_again() -> void:
	var squad := _squad()
	var hurt := _squad()
	hurt[0].hp = 1
	assert_str(OddsEstimator.squad_key(squad)).is_not_equal(OddsEstimator.squad_key(hurt))
	var est := OddsEstimator.new(_tuning(3))
	est.estimate(squad, REGION, 1)
	assert_object(est.cached(hurt, REGION, 1)).is_null()


func test_new_fight_variants_clear_the_cache() -> void:
	var est := OddsEstimator.new(_tuning(2))
	est.estimate(_squad(), REGION, 1)
	var v := FightVariants.defaults().duplicate_variants()
	est.use_variants(v)
	assert_object(est.cached(_squad(), REGION, 1)).is_not_null()
	v.choose(FightVariants.ENEMY_FACTIONS, FightVariants.FACTIONS_GENERIC)
	est.use_variants(v)
	assert_object(est.cached(_squad(), REGION, 1)).is_null()
	assert_str(est.combat_tuning.variants.option(FightVariants.ENEMY_FACTIONS)).is_equal(FightVariants.FACTIONS_GENERIC)


func test_the_switchboard_lists_the_odds_model() -> void:
	var v := FightVariants.defaults()
	assert_str(v.option(OddsEstimator.ODDS_MODEL)).is_equal(OddsEstimator.MODEL_SIMULATED)
	assert_bool(v.choose(OddsEstimator.ODDS_MODEL, OddsEstimator.MODEL_FORMULA)).is_true()
