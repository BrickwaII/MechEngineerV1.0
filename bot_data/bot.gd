class_name Bot
extends Resource
## One bot: identity, the six stats, current HP, personality, skills and
## augment slots. State and validation only.
##
## Stat ranges and the slot count come from data/ and are checked by
## BotTuning.validation_errors_for(); this class checks only what holds for
## every bot whatever the tuning.

## The six stats, in UnitStats order. Efficiency is deliberately not one.
const STAT_NAMES: Array[String] = ["hp", "attack", "defense", "speed", "elasticity", "battery_capacity"]

@export var id: String
@export var display_name: String
## Maximum HP is stats.hp; this is the current value, 0 to stats.hp.
@export var hp: int
## Elasticity is stored but has no effect yet.
@export var stats: UnitStats
@export var personality: Personality
@export var skills: Array[Skill] = []
@export var augment_slots: Array[AugmentSlot] = []


func _init(
	p_id := "",
	p_display_name := "",
	p_stats: UnitStats = null,
	p_personality: Personality = null,
	p_skills: Array[Skill] = [],
	p_augment_slots: Array[AugmentSlot] = [],
) -> void:
	id = p_id
	display_name = p_display_name
	stats = p_stats if p_stats != null else UnitStats.new()
	hp = stats.hp
	personality = p_personality if p_personality != null else Personality.new()
	skills = p_skills.duplicate()
	augment_slots = p_augment_slots.duplicate()


func get_max_hp() -> int:
	return stats.hp


## What the rest of the game sees of this bot, its skills included in order.
## A fresh copy every call, so changing it never changes the bot.
func to_summary() -> SquadMemberSummary:
	var skill_entries: Array[Dictionary] = []
	for skill in skills:
		if skill != null:
			skill_entries.append(SquadMemberSummary.make_skill(skill.display_name, skill.effect_id, skill.level))
	return SquadMemberSummary.new(
		id, display_name, hp, stats.hp, personality.get_tag(), stats.duplicate(), skill_entries)


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if id.is_empty():
		errors.append("bot has no id")
	if display_name.is_empty():
		errors.append("bot '%s' has no name" % id)
	if stats == null:
		errors.append("bot '%s' has no stats" % id)
	else:
		for stat in STAT_NAMES:
			if int(stats.get(stat)) < 0:
				errors.append("bot '%s' %s is negative" % [id, stat])
		if stats.hp <= 0:
			errors.append("bot '%s' max hp must be above 0" % id)
		if hp < 0 or hp > stats.hp:
			errors.append("bot '%s' hp %d is outside 0 to %d" % [id, hp, stats.hp])
	if personality == null:
		errors.append("bot '%s' has no personality" % id)
	else:
		errors.append_array(personality.validation_errors())
	var skill_names := {}
	for skill in skills:
		if skill == null:
			errors.append("bot '%s' has an empty skill entry" % id)
			continue
		errors.append_array(skill.validation_errors())
		if skill_names.has(skill.display_name):
			errors.append("bot '%s' holds skill '%s' twice" % [id, skill.display_name])
		skill_names[skill.display_name] = true
	for slot in augment_slots:
		if slot == null:
			errors.append("bot '%s' has an empty augment slot entry" % id)
	return errors


func is_valid() -> bool:
	return validation_errors().is_empty()
