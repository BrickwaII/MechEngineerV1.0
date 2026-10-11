class_name SkillChange
extends RefCounted
## What one fight did for one skill of one bot.
##
## With skill-progression = ranks, levels are ranks (SkillRanks) and the names
## carry them ("Mega Overcharge Shot +2"). The numbers (value_before/after) are
## what the skill does for this bot at the old and new level, computed from
## the bot's stats and the combat tuning by SkillNumbers.

var combat_skill_id: String
## The bot skill the uses counted toward, or "" when none matches.
var skill_name := ""
var uses := 0
var banked_before := 0
var banked_after := 0
var level_before := 0
var level_after := 0
## Uses the next level step takes from level_after (0 at the top), and the
## highest level, from PostFightTuning.
var uses_per_level := 0
var max_level := 0
## True when levels are named ranks.
var ranked := false
## The skill's name at level_before and level_after, rank included.
var name_before := ""
var name_after := ""
## The rank suffix alone ("+2", "Mega", "Mega +1"), "" for the base rank.
var rank_before := ""
var rank_after := ""
## True when the change reached a new tier (Mega, Ultra).
var tier_shift := false
## SkillNumbers.KIND_DAMAGE, KIND_HEAL, KIND_GUARD, or "" when unknown.
var stat_kind := ""
## Damage (against SkillNumbers' reference defense), hp healed, or percent
## guarded, before and after.
var value_before := 0.0
var value_after := 0.0
var cost_before := 0
var cost_after := 0
## What the new tier adds, in words ("pierces 50% of armor"). Empty when the
## change reached no new bonus.
var new_bonuses: Array[String] = []


func has_bot_skill() -> bool:
	return not skill_name.is_empty()


func levels_gained() -> int:
	return level_after - level_before


func is_max_level() -> bool:
	return has_bot_skill() and level_after >= max_level


func is_tier_shift() -> bool:
	return tier_shift
