class_name DebugEnemyTable
extends FixedEnemyTable
## The enemy table the battle debugger's Simulate plays (S9b): the live
## fight's enemies, in order, each with its stats as edited. Every listed
## enemy is a copy of its enemy_tables.json entry under its own id, so two
## edited copies of one enemy keep their own stats; its stats are used as
## given, not scaled again by the difficulty curve.

## Enemy id -> the stats it fights with.
var fixed_stats: Dictionary = {}


## `base`'s levels and archetypes, fielding `entries` in order: each
## {"enemy_id": id in base, "stats": UnitStats}.
static func of_lineup(base: EnemyTable, entries: Array) -> DebugEnemyTable:
	var t := DebugEnemyTable.new()
	t.enemies = base.enemies.duplicate(true)
	t.levels = base.levels.duplicate(true)
	t.archetypes = base.archetypes
	for i in entries.size():
		var e: Dictionary = entries[i]
		var source := String(e.enemy_id)
		var id := "%s__%d" % [source, i + 1]
		var def: Dictionary = (base.enemies[source] as Dictionary).duplicate(true)
		t.enemies[id] = def
		t.fixed_ids.append(id)
		t.fixed_stats[id] = e.stats
	return t


func stats_for(enemy_id: String, request: FightRequest, tuning: CombatTuning = null) -> UnitStats:
	if fixed_stats.has(enemy_id):
		var s: UnitStats = fixed_stats[enemy_id]
		return UnitStats.new(s.hp, s.attack, s.defense, s.speed, s.elasticity, s.battery_capacity)
	return super(enemy_id, request, tuning)
