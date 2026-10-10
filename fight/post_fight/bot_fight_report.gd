class_name BotFightReport
extends RefCounted
## What one bot did in one fight and what it learned from it.

var bot_id: String
var display_name: String
## How many decisions the bot made.
var decisions := 0
## Every decision's tag, in fight order.
var tags: Array[ActionTag] = []
## ActionTag label -> how many of the bot's decisions carried it.
var label_counts: Dictionary[String, int] = {}
## Personality pole -> pushes toward it.
var pole_pushes: Dictionary[String, int] = {}
var generation := Personality.MIN_GENERATION
## Raw scale values in Scale order, before and after the drift.
var personality_before: Array[float] = []
var personality_after: Array[float] = []
var skill_changes: Array[SkillChange] = []


func is_scale_active(scale: int) -> bool:
	return scale < mini(generation, Personality.SCALE_COUNT)


func shift(scale: int) -> float:
	return personality_after[scale] - personality_before[scale]


func level_ups() -> Array[SkillChange]:
	var out: Array[SkillChange] = []
	out.assign(skill_changes.filter(func(c: SkillChange) -> bool: return c.levels_gained() > 0))
	return out
