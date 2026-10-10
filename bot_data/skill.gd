class_name Skill
extends Resource
## One skill a bot holds. State only: fight/ reads effect_id and energy_cost
## and decides what the skill does.
##
## The energy cost is flat: it comes from the skill definition and does not
## change with level. Efficiency is not a stat; cheaper skills arrive later as
## learned skills.

const MIN_LEVEL := 1
const MIN_ENERGY_COST := 0

@export var display_name: String
## Names the effect fight/ implements, for example "damage_single".
@export var effect_id: String
@export var energy_cost: int = MIN_ENERGY_COST
## This bot's level in the skill. Each bot holds its own Skill, so levels are per bot.
@export var level: int = MIN_LEVEL


func _init(p_display_name := "", p_effect_id := "", p_energy_cost := MIN_ENERGY_COST, p_level := MIN_LEVEL) -> void:
	display_name = p_display_name
	effect_id = p_effect_id
	energy_cost = p_energy_cost
	level = p_level


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if display_name.is_empty():
		errors.append("skill has no name")
	if effect_id.is_empty():
		errors.append("skill '%s' has no effect id" % display_name)
	if energy_cost < MIN_ENERGY_COST:
		errors.append("skill '%s' energy cost %d is negative" % [display_name, energy_cost])
	if level < MIN_LEVEL:
		errors.append("skill '%s' level %d is below %d" % [display_name, level, MIN_LEVEL])
	return errors


func is_valid() -> bool:
	return validation_errors().is_empty()
