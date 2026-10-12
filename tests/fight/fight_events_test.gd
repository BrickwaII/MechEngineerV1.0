extends GdUnitTestSuite
## Fight raises a FightEvent for everything an action does, for the battle
## presentation, and listening changes nothing.
const Legacy := preload("res://tests/fight/legacy_switches.gd")

const H := preload("res://tests/fight/fight_test_helpers.gd")


func _fight(foe_hp := 30, foes := 2) -> Fight:
	var skills: Array[Dictionary] = [
		SquadMemberSummary.make_skill("Strike", "damage_single"),
		SquadMemberSummary.make_skill("Arc Sweep", "damage_all", 3),
		SquadMemberSummary.make_skill("Brace", "guard_self"),
		SquadMemberSummary.make_skill("Patch Up", "heal_single"),
	]
	var s := H.stats(40, 10, 2, 50, 14)
	var squad: Array[SquadMemberSummary] = [SquadMemberSummary.new("ace", "Ace", 30, 40, "test", s, skills)]
	var t := H.table({"foe": H.enemy_def("Foe", H.stats(foe_hp, 3, 0, 1, 6))}, "foe", foes)
	var fight := Fight.new(H.request(squad), 1, CombatTuning.load_default(), t)
	fight.advance()
	return fight


func _kinds(events: Array[FightEvent]) -> Array:
	return events.map(func(e: FightEvent) -> String: return FightEvent.Kind.keys()[e.kind])


func test_a_strike_raises_skill_then_hit_with_the_hp_change() -> void:
	var fight := _fight()
	var raised: Array[FightEvent] = []
	fight.event_raised.connect(func(e: FightEvent) -> void: raised.append(e))
	var foe := fight.living(Combatant.Side.ENEMY)[0]
	var hp_before := foe.hp
	assert_str(fight.submit(FightAction.use("strike", foe.id))).is_empty()
	assert_array(_kinds(raised)).is_equal(["SKILL", "HIT"])
	assert_array(fight.last_events).is_equal(raised)
	var hit := raised[1]
	assert_str(hit.actor_id).is_equal("ace")
	assert_str(hit.target_id).is_equal(foe.id)
	assert_int(hit.hp_before).is_equal(hp_before)
	assert_int(hit.hp_after).is_equal(foe.hp)
	assert_int(hit.amount).is_equal(hp_before - foe.hp)
	assert_int(hit.max_hp).is_equal(foe.max_hp)
	assert_int(hit.action_index).is_equal(fight.action_count)


func test_arc_sweep_hits_every_enemy_and_carries_its_level() -> void:
	var fight := _fight()
	var foe := fight.living(Combatant.Side.ENEMY)[0]
	fight.submit(FightAction.use("arc_sweep", foe.id))
	assert_array(_kinds(fight.last_events)).is_equal(["SKILL", "HIT", "HIT"])
	var used := fight.last_events[0]
	assert_int(used.skill_level).is_equal(3)
	assert_int(used.amount).is_equal(fight.combatant("ace").skill("arc_sweep").energy_cost)
	assert_int(used.energy_before - used.energy_after).is_equal(used.amount)


func test_a_hit_that_downs_raises_down_right_after() -> void:
	var fight := _fight(1, 1)
	var foe := fight.living(Combatant.Side.ENEMY)[0]
	fight.submit(FightAction.use("strike", foe.id))
	assert_array(_kinds(fight.last_events)).is_equal(["SKILL", "HIT", "DOWN"])
	assert_int(fight.last_events[1].hp_after).is_equal(0)


func test_heal_guard_and_wait_raise_their_own_events() -> void:
	var fight := _fight()
	fight.submit(FightAction.use("patch_up", "ace"))
	assert_array(_kinds(fight.last_events)).is_equal(["SKILL", "HEAL"])
	assert_int(fight.last_events[1].amount).is_equal(fight.last_events[1].hp_after - fight.last_events[1].hp_before)
	fight.advance()
	fight.submit(FightAction.use("brace", "ace"))
	assert_array(_kinds(fight.last_events)).is_equal(["SKILL", "GUARD"])
	assert_int(fight.last_events[1].amount).is_equal(fight.combatant("ace").guard_percent)
	fight.advance()
	var unit := fight.combatant("ace")
	unit.energy_milli = 0
	fight.submit(FightAction.wait_for("arc_sweep"))
	assert_array(_kinds(fight.last_events)).is_equal(["WAIT"])


func test_listening_changes_nothing() -> void:
	var quiet := _fight()
	var heard := _fight()
	heard.event_raised.connect(func(_e: FightEvent) -> void: pass)
	for fight in [quiet, heard]:
		while not fight.is_over():
			var unit: Combatant = fight.advance()
			if unit == null:
				break
			fight.submit(SimpleFightPolicy.new().choose(fight, unit, RandomNumberGenerator.new()))
	assert_str(heard.log_text()).is_equal(quiet.log_text())


## These tests' numbers were worked out under the old fight switches.
func before() -> void:
	Legacy.pin()


func after() -> void:
	Legacy.unpin()

