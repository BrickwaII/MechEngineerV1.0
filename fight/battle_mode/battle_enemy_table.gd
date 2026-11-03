class_name BattleEnemyTable
extends EnemyTable
## The enemy table a Battle Mode fight is fought with: the shipped enemies,
## fielding exactly the encounter's enemies (whatever the seed) at the
## encounter's scaling. Built on the EnemyTable API (pick_for, stats_for), so
## the Fight, the preview and the battle screen need nothing new, and new
## enemies and archetypes (plating) come through as they are added.

var encounter: BattleEncounter


## A copy of `base` (its enemies, levels and archetypes) for `p_encounter`.
static func for_encounter(base: EnemyTable, p_encounter: BattleEncounter) -> BattleEnemyTable:
	var t := BattleEnemyTable.new()
	t.enemies = base.enemies
	t.levels = base.levels
	t.archetypes = base.archetypes
	t.encounter = p_encounter
	return t


func pick(_level: int, _rng: RandomNumberGenerator) -> Array[String]:
	return encounter.enemy_ids.duplicate()


func pick_for(_request: FightRequest, _rng: RandomNumberGenerator,
		_faction_rule := FightVariants.FACTIONS_BY_ACT, _tuning: CombatTuning = null) -> Array[String]:
	return encounter.enemy_ids.duplicate()


## The enemy's listed stats at the encounter's scaling (the boss's for a boss).
## The difficulty-curve switch does not apply: Battle Mode has its own curve.
func stats_for(enemy_id: String, _request: FightRequest, _tuning: CombatTuning = null) -> UnitStats:
	var s := stats_of(enemy_id)
	var k: Dictionary = encounter.boss_scaling if bool(enemies[enemy_id].get("boss", false)) else encounter.scaling
	return UnitStats.new(
		_pct(s.hp, k, "hp_percent"), _pct(s.attack, k, "attack_percent"), _pct(s.defense, k, "defense_percent"),
		s.speed + int(k.get("speed_bonus", 0)), s.elasticity, s.battery_capacity)


static func _pct(value: int, k: Dictionary, key: String) -> int:
	return maxi(0, roundi(value * float(k.get(key, 100)) / 100.0))
