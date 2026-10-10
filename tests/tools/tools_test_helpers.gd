extends RefCounted
## Fixtures for the dev tools tests. Tunings are built here, not read from
## data/, so pinned numbers do not move when data/ is rebalanced.


static func combat_tuning() -> CombatTuning:
	return CombatTuning.from_dict({
		"timeline": {"action_threshold": 100, "min_charge_per_tick": 1},
		"energy": {"recharge_milli_per_battery_per_tick": 20, "recharge_floor_milli_per_tick": 100, "starting_percent": 50},
		"wait": {"recharge_bonus_percent": 100},
		"damage": {"defense_percent": 50, "min_damage": 1},
		"fight": {"max_actions": 400},
		"grid": {"base_cost": 4.0, "cost_per_defense_level": 2.0, "cost_per_energy_spent": 0.1},
		"player_skills": ["strike", "heavy_strike"],
		"skills": {
			"strike": {"name": "Strike", "energy_cost": 0, "power_percent": 100},
			"heavy_strike": {"name": "Heavy Strike", "energy_cost": 4, "power_percent": 150},
		},
	})


static func enemy_table() -> EnemyTable:
	var levels := []
	for level in range(FightRequest.MIN_DEFENSE_LEVEL, FightRequest.MAX_DEFENSE_LEVEL + 1):
		levels.append({"level": level, "count": 2, "pool": ["drone", "hound"], "rewards": {"energy": 3, "material": 1}})
	return EnemyTable.from_dict({
		"enemies": {
			"drone": {"name": "Drone", "hp": 14, "attack": 5, "defense": 2, "speed": 6, "elasticity": 1, "battery_capacity": 6, "skills": ["strike"]},
			"hound": {"name": "Hound", "hp": 20, "attack": 7, "defense": 3, "speed": 8, "elasticity": 2, "battery_capacity": 8, "skills": ["strike", "heavy_strike"]},
		},
		"levels": levels,
	})


static func bot_tuning() -> BotTuning:
	var stat_ranges := {}
	for stat in Bot.STAT_NAMES:
		stat_ranges[stat] = [1, 40]
	return BotTuning.from_dictionaries({
		"draft_size": 4, "squad_size": 3, "augment_slot_count": 2, "starting_generation": 1,
		"starting_skill_count": 2, "starting_skill_level": 1, "personality_start_range": [-0.5, 0.5],
		"stat_ranges": stat_ranges, "names": ["A", "B", "C", "D"],
	}, {"skills": [
		{"name": "Strike", "effect_id": "damage_single", "energy_cost": 0},
		{"name": "Brace", "effect_id": "guard_self", "energy_cost": 2},
		{"name": "Patch Up", "effect_id": "heal_single", "energy_cost": 3},
	]})


static func inline_bot(id: String, hp: int, attack: int, defense: int, speed: int, battery := 10) -> Dictionary:
	return {"bot": {
		"id": id, "name": id.capitalize(),
		"stats": {"hp": hp, "attack": attack, "defense": defense, "speed": speed, "elasticity": 1, "battery_capacity": battery},
		"skills": [{"name": "Strike", "level": 2}],
	}}


## Two inline bots against enemies drawn for level 1.
static func scenario(player_policy := "simple") -> FightScenario:
	return FightScenario.from_dict({
		"name": "test duo",
		"defense_level": 1,
		"squad": [inline_bot("left", 30, 7, 4, 6), inline_bot("right", 24, 9, 2, 8)],
		"player_policy": player_policy,
		"enemy_policy": "simple",
	})
