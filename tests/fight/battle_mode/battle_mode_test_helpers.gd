extends RefCounted
## Builders shared by the Battle Mode tests: a small tuning and enemy table
## whose numbers the tests can reason about.

const H := preload("res://tests/fight/fight_test_helpers.gd")


## A tuning with one curve row per fight number in `rows` (dictionaries laid
## over a one-kind beginner row), a 3-fight gauntlet with a boss at 3, and an
## endless length with a boss every 4th fight.
static func tuning(rows: Array = [{}], extra := {}) -> BattleModeTuning:
	var curve := []
	for i in rows.size():
		var row := {"from_fight": i + 1, "count": 2, "types": 1, "factions": 1, "tiers": ["beginner"], "fast": 0,
			"hp_percent": 100, "attack_percent": 100, "defense_percent": 100, "speed_bonus": 0, "defense_level": 0}
		row.merge(rows[i], true)
		curve.append(row)
	var d := {
		"lengths": {
			"gauntlet": {"name": "Gauntlet", "fights": 3, "boss_fights": [3], "boss_every": 0},
			"endless": {"name": "Endless", "fights": 0, "boss_fights": [], "boss_every": 4},
		},
		"squads": [{"id": "test", "name": "Test", "draft_seed": 5, "picks": [0, 1, 2]}],
		"tiers": ["beginner", "medium", "advanced"],
		"fast_speed": 9,
		"elite_every": 0,
		"archetypes_from_fight": 2,
		"curve": curve,
		"endless_growth": {"every": 2, "hp_percent": 10, "attack_percent": 5, "defense_percent": 5, "count": 1,
			"count_max": 4, "types": 1, "types_max": 3, "speed_bonus": 1, "speed_bonus_max": 2},
		"elite": {"extra_types": 1, "hp_percent": 150, "attack_percent": 100, "defense_percent": 100},
		"boss": {"order": ["boss_a", "boss_b"], "escorts": 1, "hp_percent": 50, "attack_percent": 100, "defense_percent": 100},
		"metrics": {"dominant_share_percent": 50, "csv_folder": "user://test_battle_mode"},
	}
	d.merge(extra, true)
	return BattleModeTuning.from_dict(d)


static func enemy(name: String, tier: String, faction := "", speed := 5, hp := 10, attack := 3, extra := {}) -> Dictionary:
	var e := H.enemy_def(name, H.stats(hp, attack, 1, speed, 6))
	e["tier"] = tier
	if not faction.is_empty():
		e["faction"] = faction
	e.merge(extra, true)
	return e


## Weak enemies in two factions plus the generic roster, two bosses, and one
## enemy that names an archetype.
static func table() -> EnemyTable:
	var defs := {
		"red_a": enemy("Red A", "beginner", "red"),
		"red_b": enemy("Red B", "beginner", "red", 10),
		"red_c": enemy("Red C", "medium", "red"),
		"blue_a": enemy("Blue A", "beginner", "blue"),
		"blue_b": enemy("Blue B", "medium", "blue", 10),
		"grey_a": enemy("Grey A", "beginner"),
		"boss_a": enemy("Boss A", "advanced", "", 4, 40, 3, {"boss": true}),
		"boss_b": enemy("Boss B", "advanced", "", 4, 40, 3, {"boss": true}),
		"charger": enemy("Charger", "beginner", "", 6, 10, 3, {"archetype": "charger"}),
	}
	return H.table(defs, "grey_a")


## A run of three sturdy test bots against the test table.
static func run(length_id := "gauntlet", seed_value := 1, t: BattleModeTuning = null) -> BattleModeRun:
	var squad := BotSquad.new([_bot("a"), _bot("b"), _bot("c")], ["a", "b", "c"], 3)
	return BattleModeRun.create(squad, length_id, seed_value, FightVariants.defaults(),
		t if t != null else tuning(), null, table())


static func _bot(id: String) -> Bot:
	var b := Bot.new()
	b.id = id
	b.display_name = id.capitalize()
	b.stats = UnitStats.new(40, 8, 3, 6, 2, 10)
	b.hp = 40
	b.personality = Personality.new()
	return b
