extends RefCounted
## Builders shared by the intent and preview tests.

const H := preload("res://tests/fight/fight_test_helpers.gd")


static func stats(hp: int, attack: int, defense: int, speed: int, battery: int) -> UnitStats:
	return H.stats(hp, attack, defense, speed, battery)


## Default tuning plus a heal skill, "repair": 2 energy, heals 100% of attack.
static func tuning_with_repair() -> CombatTuning:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CombatTuning.DEFAULT_PATH))
	d.skills["repair"] = {"name": "Repair", "energy_cost": 2, "power_percent": 100}
	return CombatTuning.from_dict(d)


## A personality with all three scales active.
static func p(aggressive_defensive := 0.0, solitary_supportive := 0.0, reactive_methodical := 0.0) -> Personality:
	return Personality.new(Personality.SCALE_COUNT, aggressive_defensive, solitary_supportive, reactive_methodical)


## A planner with the default weights and these personalities pinned by unit id.
static func planner(by_unit: Dictionary = {}) -> IntentPlanner:
	var personalities := EnemyPersonalities.new()
	for id: String in by_unit:
		personalities.by_unit[id] = by_unit[id]
	return IntentPlanner.new(IntentWeights.load_default(), personalities)


## A fight with exactly these units. Allies: {id, stats}; enemies: {id, stats,
## skills}. Either may add "hp" to start hurt.
static func fight(allies: Array, enemies: Array, tuning: CombatTuning = null) -> Fight:
	tuning = tuning if tuning != null else tuning_with_repair()
	var squad: Array[SquadMemberSummary] = []
	for a: Dictionary in allies:
		squad.append(H.member(a.id, a.stats, a.get("hp", -1)))
	var first: Dictionary = enemies[0]
	var t := H.table({"placeholder": H.enemy_def("Placeholder", first.stats)}, "placeholder")
	var f := Fight.new(H.request(squad), 1, tuning, t)
	# Swap the drawn enemy for the requested ones. The timeline shares this array.
	f.combatants.resize(allies.size())
	for e: Dictionary in enemies:
		var skills: Array[String] = []
		skills.assign(e.skills)
		var s: UnitStats = e.stats
		f.combatants.append(Combatant.new(
			e.id, String(e.id).get_slice("#", 0).capitalize() + " " + String(e.id).get_slice("#", 1),
			Combatant.Side.ENEMY, f.combatants.size(), s, int(e.get("hp", s.hp)), skills, tuning))
		f.combatants[-1].max_hp = s.hp
	return f


## Everything about a fight that a run can change, as one comparable string.
static func snapshot(f: Fight) -> String:
	var units := []
	for c in f.combatants:
		units.append([
			c.id, c.display_name, c.side, c.order, c.hp, c.max_hp, c.gauge, c.charge_per_tick,
			c.energy_milli, c.max_energy_milli, c.recharge_milli, c.wait_recharge_milli,
			c.wait_target_milli, c.wait_ticks, c.energy_spent_milli, c.skill_ids,
			[c.stats.hp, c.stats.attack, c.stats.defense, c.stats.speed, c.stats.elasticity, c.stats.battery_capacity],
		])
	return var_to_str({
		"units": units,
		"timeline_units": f.timeline.units.map(func(c: Combatant) -> String: return c.id),
		"tick": f.timeline.current_tick,
		"pending": f.pending_actor.id if f.pending_actor != null else "",
		"action_count": f.action_count,
		"action_tags": f.action_tags,
		"log": f.log_lines,
		"over": f.is_over(),
		"outcome": f.outcome,
		"timed_out": f.timed_out,
		"skills": f.tuning.skills.keys(),
	})


## The healer scenario: Bolt (fast, the only ally) against a supportive Medic
## (strike, repair) and a Grunt. Nobody is hurt at the start.
static func healer_fight() -> Fight:
	return fight(
		[{"id": "bolt", "stats": stats(60, 12, 4, 20, 10)}],
		[
			{"id": "medic#1", "stats": stats(30, 8, 2, 4, 10), "skills": ["strike", "repair"]},
			{"id": "grunt#1", "stats": stats(30, 6, 2, 4, 10), "skills": ["strike"]},
		])


static func healer_planner() -> IntentPlanner:
	return planner({"medic#1": p(0.0, 1.0, 0.0), "grunt#1": p(-0.5, -0.5, 0.0)})
