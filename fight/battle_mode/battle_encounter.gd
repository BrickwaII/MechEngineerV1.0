class_name BattleEncounter
extends RefCounted
## One Battle Mode fight before it is fought: which enemies, how tough, and
## what kind of fight it is. Built by BattleEncounterPicker; fought through
## BattleEnemyTable, so the Fight reads it like any enemy table.

enum Kind { NORMAL, ELITE, BOSS }

## 1-based number of the fight in the run.
var fight_number := 1
var kind := Kind.NORMAL
## Enemy ids in roster order (bosses first).
var enemy_ids: Array[String] = []
## The FightRequest defense level (grid cost only in Battle Mode).
var defense_level := 0
## Stat scaling of every non-boss enemy: hp_percent, attack_percent,
## defense_percent, speed_bonus.
var scaling: Dictionary = {"hp_percent": 100, "attack_percent": 100, "defense_percent": 100, "speed_bonus": 0}
## Stat scaling of the boss (same keys).
var boss_scaling: Dictionary = {"hp_percent": 100, "attack_percent": 100, "defense_percent": 100, "speed_bonus": 0}
## The factions the enemies were drawn from ("generic" for no faction).
var factions: Array[String] = []


static func kind_name(k: Kind) -> String:
	return Kind.keys()[k].to_lower()


## Distinct enemy kinds fielded: the number of "questions" the fight asks.
func distinct_types() -> int:
	var seen := {}
	for id in enemy_ids:
		seen[id] = true
	return seen.size()


func _to_string() -> String:
	return "fight %d %s: %s" % [fight_number, kind_name(kind), ", ".join(enemy_ids)]
