class_name BattleEncounterPicker
extends RefCounted
## Draws each Battle Mode fight's enemies from the curve in
## data/battle_mode/battle_mode.json (BattleModeTuning). Deterministic: the
## same fight number, length, tables and rng seed give the same encounter.
##
## Difficulty grows by asking more questions at once, as the deep dive's "Fun
## and fair" section asks: more distinct enemy kinds, more factions, faster
## enemies, then tougher tiers; stats rise only gently. Every 'elite_every'th
## fight is an elite (tiers one step up, one more kind in the same count, a
## stat bump); boss fights field the next boss in order with escorts.
##
## Candidates are read from the EnemyTable as it is: every non-boss enemy with
## a tier, grouped by its faction ("generic" for none). An enemy that names an
## archetype (S5's Charger, Plated, Scaler, ...) joins every pool from
## archetypes_from_fight on, whatever its faction, so new archetypes appear
## without a change here.


## The encounter for fight `fight_number` of a run of `length`.
static func pick(fight_number: int, length: BattleModeTuning.Length, tuning: BattleModeTuning,
		table: EnemyTable, rng: RandomNumberGenerator) -> BattleEncounter:
	var e := BattleEncounter.new()
	e.fight_number = fight_number
	var row := tuning.row_for(fight_number)
	e.defense_level = row.defense_level
	e.scaling = _scaling(row, {})
	if length.is_boss(fight_number):
		e.kind = BattleEncounter.Kind.BOSS
	elif tuning.elite_every > 0 and fight_number % tuning.elite_every == 0:
		e.kind = BattleEncounter.Kind.ELITE
	match e.kind:
		BattleEncounter.Kind.ELITE:
			var shifted: Array[String] = []
			for tier in row.tiers:
				if not tuning.tier_up(tier) in shifted:
					shifted.append(tuning.tier_up(tier))
			row.tiers = shifted
			# One more kind, within the same count: harder, not longer.
			row.types = mini(row.count, row.types + int(tuning.elite.get("extra_types", 0)))
			e.scaling = _scaling(row, tuning.elite)
		BattleEncounter.Kind.BOSS:
			var bosses := tuning.boss_order
			var boss_id := bosses[boss_index(fight_number, length) % bosses.size()]
			e.boss_scaling = _scaling(row, tuning.boss_scaling)
			e.enemy_ids.append(boss_id)
			row.count = tuning.boss_escorts
			row.types = mini(row.types, row.count)
			row.fast = mini(row.fast, row.types)
	if row.count > 0:
		e.enemy_ids.append_array(_draw(row, fight_number, tuning, table, rng, e))
	return e


## How many boss fights come before `fight_number` in a run of `length`.
static func boss_index(fight_number: int, length: BattleModeTuning.Length) -> int:
	var n := 0
	for i in range(1, fight_number):
		if length.is_boss(i):
			n += 1
	return n


## The faction an enemy belongs to, "generic" when it names none.
static func faction_of(def: Dictionary) -> String:
	var f: Variant = def.get("faction")
	return str(f) if f is String and not (f as String).is_empty() else BattleModeTuning.GENERIC_FACTION


static func _scaling(row: BattleModeTuning.Row, extra: Dictionary) -> Dictionary:
	return {
		"hp_percent": roundi(row.hp_percent * float(extra.get("hp_percent", 100)) / 100.0),
		"attack_percent": roundi(row.attack_percent * float(extra.get("attack_percent", 100)) / 100.0),
		"defense_percent": roundi(row.defense_percent * float(extra.get("defense_percent", 100)) / 100.0),
		"speed_bonus": row.speed_bonus,
	}


static func _draw(row: BattleModeTuning.Row, fight_number: int, tuning: BattleModeTuning, table: EnemyTable,
		rng: RandomNumberGenerator, into: BattleEncounter) -> Array[String]:
	var ids: Array = table.enemies.keys()
	ids.sort()
	# Faction -> candidate ids in the row's tiers; archetype enemies apart.
	var by_faction := {}
	var archetype_ids: Array[String] = []
	for id: String in ids:
		var def: Dictionary = table.enemies[id]
		if bool(def.get("boss", false)):
			continue
		var tier := str(def.get("tier", ""))
		var is_archetype := not str(def.get("archetype", "")).is_empty()
		if is_archetype and fight_number >= tuning.archetypes_from_fight and (tier.is_empty() or tier in row.tiers):
			archetype_ids.append(id)
			continue
		if is_archetype or not tier in row.tiers:
			continue
		var f := faction_of(def)
		if not by_faction.has(f):
			by_faction[f] = []
		by_faction[f].append(id)
	var factions: Array = by_faction.keys()
	factions.sort()
	factions = _shuffled(factions, rng)
	var chosen: Array[String] = []
	var candidates: Array[String] = []
	for f: String in factions:
		if chosen.size() >= row.factions:
			break
		chosen.append(f)
		candidates.append_array(by_faction[f])
	candidates.append_array(archetype_ids)
	# Too few kinds in the chosen factions: widen to every faction.
	var f_index := chosen.size()
	while _distinct(candidates) < row.types and f_index < factions.size():
		chosen.append(factions[f_index])
		candidates.append_array(by_faction[factions[f_index]])
		f_index += 1
	into.factions = chosen
	if candidates.is_empty():
		return []
	var speed_bonus := row.speed_bonus
	var fast: Array[String] = []
	var slow: Array[String] = []
	for id in _shuffled(candidates, rng):
		var bucket := fast if int(table.enemies[id].speed) + speed_bonus >= tuning.fast_speed else slow
		if not id in bucket:
			bucket.append(id)
	var kinds: Array[String] = []
	for id in fast:
		if kinds.size() >= row.fast:
			break
		kinds.append(id)
	for id in slow + fast:
		if kinds.size() >= row.types:
			break
		if not id in kinds:
			kinds.append(id)
	var out: Array[String] = kinds.duplicate()
	while out.size() < row.count:
		out.append(kinds[rng.randi_range(0, kinds.size() - 1)])
	return out


static func _distinct(items: Array[String]) -> int:
	var seen := {}
	for i in items:
		seen[i] = true
	return seen.size()


## A Fisher-Yates shuffle with `rng`, so the order replays from the seed.
static func _shuffled(items: Array, rng: RandomNumberGenerator) -> Array:
	var out := items.duplicate()
	for i in range(out.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = out[i]
		out[i] = out[j]
		out[j] = tmp
	return out
