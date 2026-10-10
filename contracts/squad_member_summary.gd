class_name SquadMemberSummary
extends Resource
## What the rest of the game sees of one squad member. Plain data.

## Keys of one entry in `skills`.
const SKILL_NAME := "name"
const SKILL_EFFECT_ID := "effect_id"
const SKILL_LEVEL := "level"

@export var id: String
@export var display_name: String
@export var hp: int
@export var max_hp: int
@export var personality_tag: String
@export var stats: UnitStats
## The skills this unit holds, in menu order. Each entry is
## {"name": String, "effect_id": String, "level": int}; build one with
## make_skill(). Empty for a unit with no known skills.
@export var skills: Array[Dictionary] = []


func _init(
	p_id := "",
	p_display_name := "",
	p_hp := 0,
	p_max_hp := 0,
	p_personality_tag := "",
	p_stats: UnitStats = null,
	p_skills: Array[Dictionary] = [],
) -> void:
	id = p_id
	display_name = p_display_name
	hp = p_hp
	max_hp = p_max_hp
	personality_tag = p_personality_tag
	stats = p_stats if p_stats != null else UnitStats.new()
	skills = p_skills.duplicate(true)


## One entry for `skills`.
static func make_skill(p_name: String, p_effect_id: String, p_level := 1) -> Dictionary:
	return {SKILL_NAME: p_name, SKILL_EFFECT_ID: p_effect_id, SKILL_LEVEL: p_level}
