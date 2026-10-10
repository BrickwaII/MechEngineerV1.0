class_name SkillChange
extends RefCounted
## What one fight did for one skill of one bot.

var combat_skill_id: String
## The bot skill the uses counted toward, or "" when none matches.
var skill_name := ""
var uses := 0
var banked_before := 0
var banked_after := 0
var level_before := 0
var level_after := 0
## Uses one level step takes, and the highest level, from PostFightTuning.
var uses_per_level := 0
var max_level := 0


func has_bot_skill() -> bool:
	return not skill_name.is_empty()


func levels_gained() -> int:
	return level_after - level_before


func is_max_level() -> bool:
	return has_bot_skill() and level_after >= max_level
