class_name SkillNumbers
extends RefCounted
## What a bot's skill does at a level, as numbers for the level-up callout:
## damage, hp healed or percent guarded, its energy cost, and its rank bonus
## effects. Computed from the bot's real stats and the combat tuning, with the
## same rules the fight resolves (CombatTuning.skill_at, DamageRules).
##
## Damage is against a reference target with reference_defense
## (data/post_fight/post_fight.json "level_up_callout"), so the number shows
## the skill's own growth rather than one enemy's armor. Damage and healing
## are exact, before the fight rounds down (DamageRules floors each hit), so a
## +6% step shows ("8 -> 8.5 dmg") even when one hit would round to the same.

const KIND_DAMAGE := "dmg"
const KIND_HEAL := "hp"
const KIND_GUARD := "% guard"


## {kind, value (float), cost, bonuses: {key: percent}} for `combat_skill_id`
## held at `level` by a bot with `stats`. Empty for an unknown skill.
static func at_level(stats: UnitStats, combat_skill_id: String, level: int, combat: CombatTuning, reference_defense: int) -> Dictionary:
	var skill := combat.skill_at(combat_skill_id, level)
	if skill == null:
		return {}
	var out := {"cost": skill.energy_cost, "bonuses": {}}
	for key in SkillRanks.BONUS_KEYS:
		var v: int = skill.get(key)
		if v > 0:
			out.bonuses[key] = v
	if skill.is_heal():
		out.kind = KIND_HEAL
		out.value = maxf(0.0, stats.attack * skill.power_percent / 100.0)
	elif skill.is_guard():
		out.kind = KIND_GUARD
		out.value = float(skill.power_percent)
	else:
		# DamageRules.damage() before its integer division and minimum.
		var armor := reference_defense * combat.defense_percent * (100 - clampi(skill.pierce_percent, 0, 100)) / 10000.0
		out.kind = KIND_DAMAGE
		out.value = maxf(float(combat.min_damage), stats.attack * skill.power_percent / 100.0 - armor)
	return out


## "8", "8.5": a number with at most one decimal.
static func format(value: float) -> String:
	var tenths := snappedf(value, 0.1)
	return str(int(tenths)) if is_equal_approx(tenths, roundf(tenths)) else "%.1f" % tenths


## Bonus effects in `after` that are new or bigger than in `before`, in words.
static func new_bonuses(before: Dictionary, after: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var b: Dictionary = before.get("bonuses", {})
	for key: String in after.get("bonuses", {}):
		var v: int = after.bonuses[key]
		if v > int(b.get(key, 0)):
			out.append(describe(key, v))
	return out


## One bonus effect as its keyword and number: "Pierce 50%". The keywords'
## meanings are in data/ui/glossary.json.
static func describe(key: String, percent: int) -> String:
	match key:
		"pierce_percent":
			return "Pierce %d%%" % percent
		"weakest_bonus_percent":
			return "Weakest +%d%%" % percent
		"heal_guard_percent":
			return "Guard %d%% on heals" % percent
		"reflect_percent":
			return "Reflect %d%%" % percent
	return "%s %d%%" % [key, percent]


## Fills `change`'s names, and with `combat` its numbers, for `stats`.
static func fill(change: SkillChange, stats: UnitStats, combat: CombatTuning, tuning: PostFightTuning) -> void:
	if not change.has_bot_skill():
		return
	change.ranked = tuning.uses_ranks()
	if change.ranked:
		var ranks := tuning.ranks
		change.name_before = ranks.rank_name(change.skill_name, change.level_before)
		change.name_after = ranks.rank_name(change.skill_name, change.level_after)
		change.rank_before = ranks.rank_label(change.level_before)
		change.rank_after = ranks.rank_label(change.level_after)
		change.tier_shift = ranks.tier_of(change.level_after) > ranks.tier_of(change.level_before)
	else:
		change.name_before = change.skill_name
		change.name_after = change.skill_name
		change.rank_before = "Lv%d" % change.level_before
		change.rank_after = "Lv%d" % change.level_after
	if combat == null:
		return
	var before := at_level(stats, change.combat_skill_id, change.level_before, combat, tuning.reference_defense)
	var after := at_level(stats, change.combat_skill_id, change.level_after, combat, tuning.reference_defense)
	if before.is_empty() or after.is_empty():
		return
	change.stat_kind = after.kind
	change.value_before = before.value
	change.value_after = after.value
	change.cost_before = before.cost
	change.cost_after = after.cost
	change.new_bonuses = new_bonuses(before, after)
