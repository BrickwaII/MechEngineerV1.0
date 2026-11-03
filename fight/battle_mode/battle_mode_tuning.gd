class_name BattleModeTuning
extends RefCounted
## Every Battle Mode number, loaded from data/battle_mode/battle_mode.json:
## run lengths, preset squads, the difficulty curve, elites, bosses and the
## fun metrics' thresholds. Tests may build one with from_dict() and change
## fields directly.

const DEFAULT_PATH := "res://data/battle_mode/battle_mode.json"
const GENERIC_FACTION := "generic"


## How long a run lasts.
class Length:
	var id := ""
	var name := ""
	var description := ""
	## Fights in the run; 0 is endless (until the squad falls).
	var fights := 0
	## Fight numbers (1-based) that are boss fights.
	var boss_fights: Array[int] = []
	## Every Nth fight is also a boss fight; 0 for none.
	var boss_every := 0

	func is_endless() -> bool:
		return fights <= 0

	func is_boss(fight_number: int) -> bool:
		return fight_number in boss_fights or (boss_every > 0 and fight_number % boss_every == 0)


## A ready-made squad: a draft seed and the draft positions fielded.
class SquadPreset:
	var id := ""
	var name := ""
	var description := ""
	var draft_seed := 0
	var picks: Array[int] = []


## One step of the difficulty curve. Applies from `from_fight` on.
class Row:
	var from_fight := 1
	var count := 1
	var types := 1
	var factions := 1
	var tiers: Array[String] = []
	var fast := 0
	var hp_percent := 100
	var attack_percent := 100
	var defense_percent := 100
	var speed_bonus := 0
	var defense_level := 0

	func copy() -> Row:
		var r := Row.new()
		r.from_fight = from_fight
		r.count = count
		r.types = types
		r.factions = factions
		r.tiers = tiers.duplicate()
		r.fast = fast
		r.hp_percent = hp_percent
		r.attack_percent = attack_percent
		r.defense_percent = defense_percent
		r.speed_bonus = speed_bonus
		r.defense_level = defense_level
		return r


## Length id -> Length, in file order.
var lengths: Dictionary[String, Length] = {}
var squads: Array[SquadPreset] = []
## Weakest to strongest.
var tiers: Array[String] = []
var fast_speed := 9
var elite_every := 0
var archetypes_from_fight := 1
## Sorted by from_fight; the first starts at fight 1.
var curve: Array[Row] = []
## endless_growth: every, hp_percent, attack_percent, defense_percent, count,
## count_max, types, types_max, speed_bonus, speed_bonus_max.
var endless_growth: Dictionary = {}
## elite: extra_types, hp_percent, attack_percent, defense_percent.
var elite: Dictionary = {}
var boss_order: Array[String] = []
var boss_escorts := 0
## boss hp_percent, attack_percent, defense_percent.
var boss_scaling: Dictionary = {}
var dominant_share_percent := 50
var csv_folder := "user://battle_mode"
## Problems found while reading, worded for the person editing the file.
var load_errors: Array[String] = []


## The shipped file; read from disk once, a fresh object every call.
static func load_default() -> BattleModeTuning:
	var d: Variant = JsonFile.read_object_cached(DEFAULT_PATH)
	return from_dict(d) if d != null else load_file(DEFAULT_PATH)


static func load_file(path: String) -> BattleModeTuning:
	var d: Variant = JsonFile.read_object(path)
	if d == null:
		push_error("BattleModeTuning: cannot read %s" % path)
		return null
	return from_dict(d)


static func from_dict(d: Dictionary) -> BattleModeTuning:
	var t := BattleModeTuning.new()
	var r := DataReader.new(t.load_errors, "battle_mode")
	var lengths_d: Variant = r.lookup(d, "lengths")
	if lengths_d is Dictionary:
		for id: String in lengths_d:
			var e: Dictionary = lengths_d[id]
			var l := Length.new()
			l.id = id
			l.name = str(e.get("name", id))
			l.description = str(e.get("description", ""))
			l.fights = int(e.get("fights", 0))
			for n: Variant in e.get("boss_fights", []):
				l.boss_fights.append(int(n))
			l.boss_every = int(e.get("boss_every", 0))
			t.lengths[id] = l
	for e: Variant in r.list(d, "squads"):
		if not e is Dictionary:
			continue
		var p := SquadPreset.new()
		p.id = str(e.get("id", ""))
		p.name = str(e.get("name", p.id))
		p.description = str(e.get("description", ""))
		p.draft_seed = int(e.get("draft_seed", 0))
		for i: Variant in e.get("picks", []):
			p.picks.append(int(i))
		t.squads.append(p)
	for tier: Variant in r.list(d, "tiers"):
		t.tiers.append(str(tier))
	t.fast_speed = int(r.num(d, "fast_speed"))
	t.elite_every = int(r.num(d, "elite_every"))
	t.archetypes_from_fight = int(r.num(d, "archetypes_from_fight"))
	for e: Variant in r.list(d, "curve"):
		if e is Dictionary:
			t.curve.append(_row(e))
	t.curve.sort_custom(func(a: Row, b: Row) -> bool: return a.from_fight < b.from_fight)
	var growth: Variant = r.lookup(d, "endless_growth")
	t.endless_growth = growth if growth is Dictionary else {}
	var elite_d: Variant = r.lookup(d, "elite")
	t.elite = elite_d if elite_d is Dictionary else {}
	var boss_d: Variant = r.lookup(d, "boss")
	if boss_d is Dictionary:
		for id: Variant in boss_d.get("order", []):
			t.boss_order.append(str(id))
		t.boss_escorts = int(boss_d.get("escorts", 0))
		t.boss_scaling = boss_d
	t.dominant_share_percent = int(r.num(d, "metrics.dominant_share_percent"))
	var folder: Variant = r.lookup(d, "metrics.csv_folder")
	t.csv_folder = str(folder) if folder != null else t.csv_folder
	return t


static func _row(e: Dictionary) -> Row:
	var row := Row.new()
	row.from_fight = int(e.get("from_fight", 1))
	row.count = int(e.get("count", 1))
	row.types = int(e.get("types", 1))
	row.factions = int(e.get("factions", 1))
	for tier: Variant in e.get("tiers", []):
		row.tiers.append(str(tier))
	row.fast = int(e.get("fast", 0))
	row.hp_percent = int(e.get("hp_percent", 100))
	row.attack_percent = int(e.get("attack_percent", 100))
	row.defense_percent = int(e.get("defense_percent", 100))
	row.speed_bonus = int(e.get("speed_bonus", 0))
	row.defense_level = int(e.get("defense_level", 0))
	return row


func length(id: String) -> Length:
	return lengths.get(id)


func squad_preset(id: String) -> SquadPreset:
	for p in squads:
		if p.id == id:
			return p
	return null


## The curve row for fight `fight_number` (1-based). Past the last row it
## keeps growing by endless_growth.
func row_for(fight_number: int) -> Row:
	var base: Row = curve[0]
	for row in curve:
		if row.from_fight <= fight_number:
			base = row
	var row := base.copy()
	var last: Row = curve[-1]
	var every := int(endless_growth.get("every", 0))
	if base != last or every <= 0:
		return row
	@warning_ignore("integer_division")
	var steps := (fight_number - last.from_fight) / every
	if steps <= 0:
		return row
	row.hp_percent += steps * int(endless_growth.get("hp_percent", 0))
	row.attack_percent += steps * int(endless_growth.get("attack_percent", 0))
	row.defense_percent += steps * int(endless_growth.get("defense_percent", 0))
	row.count = mini(maxi(row.count, int(endless_growth.get("count_max", row.count))),
		row.count + steps * int(endless_growth.get("count", 0)))
	row.types = mini(maxi(row.types, int(endless_growth.get("types_max", row.types))),
		row.types + steps * int(endless_growth.get("types", 0)))
	row.speed_bonus = mini(maxi(row.speed_bonus, int(endless_growth.get("speed_bonus_max", row.speed_bonus))),
		row.speed_bonus + steps * int(endless_growth.get("speed_bonus", 0)))
	return row


## `tier` shifted `steps` up the tier list, capped at the top.
func tier_up(tier: String, steps := 1) -> String:
	var i := tiers.find(tier)
	if i < 0:
		return tier
	return tiers[mini(tiers.size() - 1, i + steps)]


## Problems in the tuning, checked against `enemies` (an EnemyTable); empty
## when every number and name is usable.
func validate(enemies: EnemyTable) -> Array[String]:
	var problems: Array[String] = load_errors.duplicate()
	if lengths.is_empty():
		problems.append("battle_mode has no lengths")
	for id in lengths:
		var l: Length = lengths[id]
		if l.fights < 0:
			problems.append("length %s has negative fights" % id)
		if l.is_endless() and l.boss_every <= 0 and l.boss_fights.is_empty():
			problems.append("length %s is endless with no bosses" % id)
	var preset_ids := {}
	for p in squads:
		if p.id.is_empty():
			problems.append("a preset squad has no id")
		if preset_ids.has(p.id):
			problems.append("preset squad %s is listed twice" % p.id)
		preset_ids[p.id] = true
		if p.picks.is_empty():
			problems.append("preset squad %s fields nobody" % p.id)
	if tiers.is_empty():
		problems.append("battle_mode has no tiers")
	if curve.is_empty():
		problems.append("battle_mode has no curve")
	elif curve[0].from_fight != 1:
		problems.append("the curve's first row must start at fight 1")
	for row in curve:
		var where := "curve row from fight %d" % row.from_fight
		if row.count < 1:
			problems.append("%s fields no enemies" % where)
		if row.types < 1 or row.types > row.count:
			problems.append("%s: types must be 1 to count" % where)
		if row.factions < 1:
			problems.append("%s: factions must be at least 1" % where)
		if row.fast < 0 or row.fast > row.types:
			problems.append("%s: fast must be 0 to types" % where)
		if row.defense_level < FightRequest.MIN_DEFENSE_LEVEL or row.defense_level > FightRequest.MAX_DEFENSE_LEVEL:
			problems.append("%s: defense_level must be %d to %d" % [
				where, FightRequest.MIN_DEFENSE_LEVEL, FightRequest.MAX_DEFENSE_LEVEL])
		if row.tiers.is_empty():
			problems.append("%s draws from no tier" % where)
		for tier in row.tiers:
			if not tier in tiers:
				problems.append("%s names unknown tier %s" % [where, tier])
		for pct in [row.hp_percent, row.attack_percent, row.defense_percent]:
			if pct <= 0:
				problems.append("%s: stat percents must be above 0" % where)
	if boss_order.is_empty():
		problems.append("battle_mode has no bosses")
	if enemies != null:
		for id in boss_order:
			if not enemies.enemies.has(id):
				problems.append("boss %s is not in the enemy table" % id)
	return problems
