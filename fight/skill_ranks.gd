class_name SkillRanks
extends RefCounted
## Named skill ranks, from data/combat/skill_ranks.json: Beam, Beam +1 ...
## Beam +5, Mega Beam, Mega Beam +1 ... Mega Beam +5, Ultra Beam.
##
## A rank is a whole number from 1 (the base skill) to max_rank(). It is what
## a bot Skill stores as its level when skill-progression is "ranks" (the
## default; data/variants/variants.json). Small steps add step_power_percent
## of the skill's power each; a tier shift adds tier_power_percent and the
## tier's bonus effects (pierce, weakest bonus, heal guard, reflect).
## TODO(decision: skill-ranks): every number is a first guess.

const DEFAULT_PATH := "res://data/combat/skill_ranks.json"
const BONUS_KEYS: Array[String] = ["pierce_percent", "weakest_bonus_percent", "heal_guard_percent", "reflect_percent"]

class Tier:
	var id: String
	var prefix: String
	var steps: int
	## [first, last] SkillFx level this tier's ranks spread over.
	var fx_levels: Vector2i

var tiers: Array[Tier] = []
var step_power_percent: int
var tier_power_percent: int
## uses_to_next[r - 1] takes rank r to r + 1.
var uses_to_next: Array[int] = []
## Combat skill id -> tier id -> {bonus key: percent}.
var bonuses: Dictionary = {}

static var _cached: SkillRanks


## The data file, read once.
static func load_default() -> SkillRanks:
	if _cached == null:
		_cached = load_file(DEFAULT_PATH)
	return _cached


static func load_file(path: String) -> SkillRanks:
	var d: Variant = JsonFile.read_object(path)
	if d == null:
		push_error("SkillRanks: cannot read %s" % path)
		return null
	return from_dict(d)


static func from_dict(d: Dictionary) -> SkillRanks:
	var r := SkillRanks.new()
	for t: Dictionary in d.get("tiers", []):
		var tier := Tier.new()
		tier.id = String(t.get("id", ""))
		tier.prefix = String(t.get("prefix", ""))
		tier.steps = int(t.get("steps", 0))
		var fx: Array = t.get("fx_levels", [1, 1])
		tier.fx_levels = Vector2i(int(fx[0]), int(fx[1]))
		r.tiers.append(tier)
	r.step_power_percent = int(d.get("step_power_percent", 0))
	r.tier_power_percent = int(d.get("tier_power_percent", 0))
	for n: Variant in d.get("uses_to_next", []):
		r.uses_to_next.append(int(n))
	var b: Dictionary = d.get("bonuses", {})
	for id: String in b:
		if not id.begins_with("_"):
			r.bonuses[id] = (b[id] as Dictionary).duplicate(true)
	return r


## The highest rank: one per step of every tier, plus each tier's own rank.
func max_rank() -> int:
	var total := 0
	for tier in tiers:
		total += 1 + tier.steps
	return maxi(1, total)


## Index of the tier `rank` is in (0 for the base tier).
func tier_of(rank: int) -> int:
	var first := 1
	for i in tiers.size():
		if rank < first + 1 + tiers[i].steps:
			return i
		first += 1 + tiers[i].steps
	return maxi(0, tiers.size() - 1)


## The step inside its tier: 0 for the tier's own rank, then 1 to steps.
func step_of(rank: int) -> int:
	var r := clampi(rank, 1, max_rank())
	var first := 1
	for i in tier_of(r):
		first += 1 + tiers[i].steps
	return r - first


## True when `rank` is the first rank of a tier above the base one.
func is_tier_shift(rank: int) -> bool:
	return rank > 1 and rank <= max_rank() and step_of(rank) == 0


## "Mega Overcharge Shot +2", "Overcharge Shot", "Ultra Overcharge Shot".
func rank_name(skill_name: String, rank: int) -> String:
	var r := clampi(rank, 1, max_rank())
	var prefix := tiers[tier_of(r)].prefix if not tiers.is_empty() else ""
	var full := ("%s %s" % [prefix, skill_name]) if not prefix.is_empty() else skill_name
	var step := step_of(r)
	return full if step == 0 else "%s +%d" % [full, step]


## The rank's suffix alone: "+2", "Mega", "Mega +2", or "" for the base rank.
func rank_label(rank: int) -> String:
	var r := clampi(rank, 1, max_rank())
	var prefix := tiers[tier_of(r)].prefix if not tiers.is_empty() else ""
	var step := "+%d" % step_of(r) if step_of(r) > 0 else ""
	return ("%s %s" % [prefix, step]).strip_edges()


## Power added at `rank`, in percent of the skill's base power.
func power_bonus_percent(rank: int) -> int:
	var r := clampi(rank, 1, max_rank())
	var tier := tier_of(r)
	var steps_before := 0
	for i in tier:
		steps_before += tiers[i].steps
	return (steps_before + step_of(r)) * step_power_percent + tier * tier_power_percent


## The bonus effects a skill has at `rank`: {bonus key: percent}, from the
## highest tier reached that lists the skill.
func bonuses_at(combat_skill_id: String, rank: int) -> Dictionary:
	var by_tier: Dictionary = bonuses.get(combat_skill_id, {})
	var out := {}
	for i in tier_of(clampi(rank, 1, max_rank())) + 1:
		if by_tier.has(tiers[i].id):
			out = (by_tier[tiers[i].id] as Dictionary).duplicate()
	return out


## The SkillFx level (1 to 10) to draw `rank` with: each tier spreads its
## ranks over its fx_levels, so a tier shift jumps to a new look.
func fx_level(rank: int) -> int:
	if tiers.is_empty():
		return 1
	var r := clampi(rank, 1, max_rank())
	var tier := tiers[tier_of(r)]
	if tier.steps <= 0:
		return tier.fx_levels.y
	@warning_ignore("integer_division")
	return tier.fx_levels.x + step_of(r) * (tier.fx_levels.y - tier.fx_levels.x) / tier.steps


## Uses that take `rank` to the next one; 0 at the top rank.
func uses_to_rank_up(rank: int) -> int:
	if rank < 1 or rank >= max_rank() or rank > uses_to_next.size():
		return 0
	return uses_to_next[rank - 1]


## A copy of `base` as a unit at `rank` holds it, named `skill_name` ("" keeps
## the base's name) with the rank in the name. A guard never blocks more than
## `max_guard_percent`. The cost does not change.
@warning_ignore("integer_division")
func apply(base: CombatSkill, rank: int, skill_name: String, max_guard_percent: int) -> CombatSkill:
	var c := CombatSkill.new(base.id, base.display_name, base.energy_cost, base.power_percent, base.effect, base.target)
	c.level = clampi(rank, 1, max_rank())
	c.display_name = rank_name(skill_name if not skill_name.is_empty() else base.display_name, c.level)
	c.names_rank = true
	c.fx_level = fx_level(c.level)
	c.power_percent = base.power_percent * (100 + power_bonus_percent(c.level)) / 100
	if c.is_guard():
		c.power_percent = mini(c.power_percent, max_guard_percent)
	var b := bonuses_at(base.id, c.level)
	c.pierce_percent = clampi(int(b.get("pierce_percent", 0)), 0, 100)
	c.weakest_bonus_percent = maxi(0, int(b.get("weakest_bonus_percent", 0)))
	c.heal_guard_percent = clampi(int(b.get("heal_guard_percent", 0)), 0, max_guard_percent)
	c.reflect_percent = maxi(0, int(b.get("reflect_percent", 0)))
	return c


## The highest rank whose power is no more than a flat level's
## (100 + (level - 1) x `percent_per_level` percent). Converts format-1 saves.
func rank_for_flat_level(flat_level: int, percent_per_level: int) -> int:
	var flat_bonus := (maxi(1, flat_level) - 1) * percent_per_level
	var best := 1
	for r in range(1, max_rank() + 1):
		if power_bonus_percent(r) <= flat_bonus:
			best = r
	return best


## Problems in the data; empty when usable.
func validate() -> Array[String]:
	var problems: Array[String] = []
	if tiers.is_empty():
		problems.append("no tiers")
	if uses_to_next.size() != max_rank() - 1:
		problems.append("uses_to_next has %d entries, needs %d" % [uses_to_next.size(), max_rank() - 1])
	for n in uses_to_next:
		if n < 1:
			problems.append("uses_to_next entries must be at least 1")
	for tier in tiers:
		if tier.steps < 0:
			problems.append("tier %s has negative steps" % tier.id)
		if tier.fx_levels.x < 1 or tier.fx_levels.x > tier.fx_levels.y:
			problems.append("tier %s fx_levels must be low to high from 1" % tier.id)
	for id: String in bonuses:
		for tier_id: String in bonuses[id]:
			if not tiers.any(func(t: Tier) -> bool: return t.id == tier_id):
				problems.append("bonus %s.%s names no tier" % [id, tier_id])
			for key: String in bonuses[id][tier_id]:
				if not key in BONUS_KEYS:
					problems.append("bonus %s.%s.%s is not a bonus" % [id, tier_id, key])
	return problems
