extends GdUnitTestSuite
## BattleFightRecorder: what it measures matches the fight.

const B := preload("res://tests/fight/battle_mode/battle_mode_test_helpers.gd")
const H := preload("res://tests/fight/fight_test_helpers.gd")


func _play(fight: Fight, rec: BattleFightRecorder, policy: FightPolicy) -> void:
	var rng := HeadlessFightRunner.policy_rng(fight.fight_seed)
	var fallback := SimpleFightPolicy.new()
	var actor := fight.advance()
	while actor != null:
		HeadlessFightRunner.play_turn(fight, actor,
			policy if actor.side == Combatant.Side.PLAYER else IntentFightPolicy.new(), fallback, rng)
		rec.after_action(fight)
		actor = fight.advance()


func _duel(ally: UnitStats, tuning: CombatTuning = null) -> Fight:
	var foe := B.enemy("Foe", "beginner", "", 4, 60, 2)
	var table := H.table({"foe": foe}, "foe")
	return Fight.new(H.request([H.member("a", ally)]), 1, tuning, table)


func test_turns_and_action_uses_count_the_squads_decisions() -> void:
	var fight := _duel(H.stats(40, 6, 2, 6, 10))
	var rec := BattleFightRecorder.new(fight)
	_play(fight, rec, PatientFightPolicy.new())
	var r := rec.finish(fight, null)
	var squad_tags := fight.action_tags.filter(func(t: String) -> bool: return t.begins_with("a:"))
	assert_int(r.turns).is_equal(squad_tags.size())
	var total := 0
	for id: String in r.action_uses:
		total += int(r.action_uses[id])
	assert_int(total).is_equal(r.turns)
	assert_int(r.actions).is_equal(fight.action_count)
	assert_bool(r.victory).is_equal(fight.outcome == FightResult.Outcome.VICTORY)


func test_hp_lost_is_start_minus_end() -> void:
	var fight := _duel(H.stats(40, 6, 2, 6, 10))
	var start := fight.combatant("a").hp
	var rec := BattleFightRecorder.new(fight)
	_play(fight, rec, SimpleFightPolicy.new())
	var r := rec.finish(fight, null)
	assert_int(r.hp_start).is_equal(start)
	assert_int(r.hp_lost()).is_equal(start - fight.combatant("a").hp)
	assert_int(r.hp_max).is_equal(40)


func test_energy_spent_matches_the_fight() -> void:
	var fight := _duel(H.stats(40, 6, 2, 6, 10))
	var rec := BattleFightRecorder.new(fight)
	_play(fight, rec, SimpleFightPolicy.new())
	assert_int(rec.finish(fight, null).energy_spent_milli).is_equal(fight.energy_spent_milli(Combatant.Side.PLAYER))


## A bot that never waits and stays up recharges ticks x rate in all; what it
## holds at the end is its start plus that, minus what it spent and wasted.
func test_wasted_energy_balances_the_energy_books() -> void:
	var tuning := CombatTuning.load_default()
	tuning.starting_energy_percent = 100
	# A small battery and a cheap Strike: the bot sits at full and wastes.
	var fight := _duel(H.stats(200, 3, 9, 6, 3), tuning)
	var bot := fight.combatant("a")
	var start := bot.energy_milli
	var rec := BattleFightRecorder.new(fight)
	_play(fight, rec, SimpleFightPolicy.new())
	assert_bool(bot.is_alive()).is_true()
	var r := rec.finish(fight, null)
	var recharged := fight.timeline.current_tick * bot.recharge_milli
	assert_int(r.energy_wasted_milli).is_greater(0)
	assert_int(r.energy_wasted_milli).is_equal(start + recharged - bot.energy_spent_milli - bot.energy_milli)


func test_a_bot_that_spends_what_it_gets_wastes_nothing() -> void:
	var tuning := CombatTuning.load_default()
	tuning.starting_energy_percent = 0
	var fight := _duel(H.stats(200, 3, 9, 6, 20), tuning)
	var rec := BattleFightRecorder.new(fight)
	_play(fight, rec, SimpleFightPolicy.new())
	assert_int(rec.finish(fight, null).energy_wasted_milli).is_equal(0)


func test_combos_setups_and_staggers_come_from_events() -> void:
	var fight := _duel(H.stats(40, 6, 2, 6, 10))
	var rec := BattleFightRecorder.new(fight)
	var hit := FightEvent.new(FightEvent.Kind.HIT, 1, "a", "foe#1", "heavy_strike")
	hit.payoff_bonus_percent = 50
	var plain := FightEvent.new(FightEvent.Kind.HIT, 1, "a", "foe#1", "strike")
	var applied := FightEvent.new(FightEvent.Kind.STATUS_APPLIED, 1, "a", "foe#1", "shred")
	var stagger := FightEvent.new(FightEvent.Kind.STAGGER, 1, "a", "foe#1", "strike")
	var enemy_combo := FightEvent.new(FightEvent.Kind.HIT, 2, "foe#1", "a", "strike")
	enemy_combo.status_bonus_percent = 50
	for e in [hit, plain, applied, stagger, enemy_combo]:
		fight.event_raised.emit(e)
	var r := rec.finish(fight, null)
	assert_int(r.combos).is_equal(1)
	assert_int(r.setups).is_equal(1)
	assert_int(r.staggers).is_equal(1)


func test_share_and_domination() -> void:
	var r := BattleFightRecord.new()
	r.action_uses = {"strike": 6, "heavy_strike": 3, "wait": 1}
	r.turns = 10
	assert_str(r.top_action()).is_equal("strike")
	assert_int(r.top_share_percent()).is_equal(60)
	assert_bool(r.is_dominated(50)).is_true()
	assert_bool(r.is_dominated(60)).is_false()
	assert_str(BattleFightRecord.uses_text(r.action_uses)).is_equal("heavy_strike=3 strike=6 wait=1")


func test_top_action_ties_go_alphabetically() -> void:
	assert_str(BattleFightRecord.top_of({"wait": 2, "strike": 2, "brace": 1})).is_equal("strike")


## A battle screen builds its fight and runs time to the first decision
## before the recorder can attach; the waste of those ticks still counts.
func test_attaching_after_the_first_advance_records_the_same() -> void:
	var tuning := CombatTuning.load_default()
	tuning.starting_energy_percent = 100
	var early := _duel(H.stats(200, 3, 9, 6, 3), tuning)
	var early_rec := BattleFightRecorder.new(early)
	_play(early, early_rec, SimpleFightPolicy.new())
	var late := _duel(H.stats(200, 3, 9, 6, 3), tuning)
	late.advance()
	assert_int(late.timeline.current_tick).is_greater(0)
	var late_rec := BattleFightRecorder.new(late)
	_play(late, late_rec, SimpleFightPolicy.new())
	assert_array(late_rec.finish(late, null).csv_row("x")).is_equal(early_rec.finish(early, null).csv_row("x"))
