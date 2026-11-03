extends GdUnitTestSuite
## Seeded opening gauges (combat rework S9, the sandbox's seed variation):
## CombatTuning.opening_gauge_spread_percent gives each unit a head start of 0
## to that percent of a turn, drawn from the fight's seed after the enemies.

const SANDBOX := "res://data/scenarios/sandbox_3v3.json"


func _request(level := 2) -> FightRequest:
	return FightRequest.new(FightRequest.Kind.ATTACK, "t", level, StubSquadProvider.new().get_squad())


func _tuning(spread: int) -> CombatTuning:
	var t := CombatTuning.load_default()
	t.opening_gauge_spread_percent = spread
	return t


func test_the_shipped_tuning_starts_every_unit_empty() -> void:
	assert_int(CombatTuning.load_default().opening_gauge_spread_percent).is_equal(0)
	for seed_value in range(1, 6):
		for c in Fight.new(_request(), seed_value).combatants:
			assert_int(c.gauge).is_equal(0)


func test_no_spread_draws_nothing_so_the_enemies_are_unchanged() -> void:
	for seed_value in range(1, 8):
		var plain := Fight.new(_request(4), seed_value)
		var spread := Fight.new(_request(4), seed_value, _tuning(60))
		assert_array(spread.combatants.map(func(c: Combatant) -> String: return c.id)).is_equal(
			plain.combatants.map(func(c: Combatant) -> String: return c.id))


func test_each_unit_opens_within_the_spread_and_the_seed_repeats_it() -> void:
	var tuning := _tuning(50)
	var most := tuning.turn_threshold() / 2
	var seen_nonzero := false
	for seed_value in range(1, 21):
		var a := Fight.new(_request(), seed_value, tuning)
		var b := Fight.new(_request(), seed_value, tuning)
		for i in a.combatants.size():
			assert_int(a.combatants[i].gauge).is_between(0, most)
			assert_int(b.combatants[i].gauge).is_equal(a.combatants[i].gauge)
			seen_nonzero = seen_nonzero or a.combatants[i].gauge > 0
	assert_bool(seen_nonzero).is_true()


func test_a_head_start_changes_who_acts_first() -> void:
	var firsts := {}
	for seed_value in range(1, 31):
		var fight := Fight.new(_request(), seed_value, _tuning(90))
		firsts[fight.advance().id] = true
	assert_int(firsts.size()).is_greater(1)


func test_the_opening_gauge_is_in_the_log() -> void:
	var fight := Fight.new(_request(), 3, _tuning(50))
	var opened := fight.combatants.filter(func(c: Combatant) -> bool: return c.gauge > 0)
	assert_int(opened.size()).is_greater(0)
	assert_str(fight.log_text()).contains("opening gauge %d" % opened[0].gauge)
	assert_str(Fight.new(_request(), 3).log_text()).not_contains("opening gauge")


func test_a_sandbox_fight_replays_from_request_seed_and_decisions() -> void:
	var resolved := ScenarioFiles.load_scenario(SANDBOX).resolve()
	for seed_value in [1, 4, 9]:
		var fight := resolved.start(seed_value).run_to_end().fight
		var again := FightLog.replay(fight.request, seed_value, fight.events, resolved.tuning, resolved.enemy_table)
		assert_array(FightLog.lines(again.events)).is_equal(FightLog.lines(fight.events))
		assert_int(again.outcome).is_equal(fight.outcome)


func test_the_spread_is_validated() -> void:
	assert_array(_tuning(50).validate()).is_empty()
	assert_str(", ".join(_tuning(100).validate())).contains("gauge_spread_percent")
	assert_str(", ".join(_tuning(-1).validate())).contains("gauge_spread_percent")
