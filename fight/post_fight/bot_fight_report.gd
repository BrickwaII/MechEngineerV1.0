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
## Personality end -> weighted pushes toward it.
var pole_pushes: Dictionary[String, float] = {}
var generation := Personality.MIN_GENERATION
## Every personality end in Personality.ENDS order, before and after the drift.
var personality_before: Array[float] = []
var personality_after: Array[float] = []
var skill_changes: Array[SkillChange] = []


## How much end `index` (Personality.ENDS order) grew. Never negative.
func growth(index: int) -> float:
	return personality_after[index] - personality_before[index]


## True when any end grew.
func personality_grew() -> bool:
	for i in personality_after.size():
		if not is_zero_approx(growth(i)):
			return true
	return false


func level_ups() -> Array[SkillChange]:
	var out: Array[SkillChange] = []
	out.assign(skill_changes.filter(func(c: SkillChange) -> bool: return c.levels_gained() > 0))
	return out
