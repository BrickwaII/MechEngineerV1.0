class_name BotJson
extends RefCounted
## Turns a Bot into a plain dictionary and back, for bots written inline in a
## scenario file:
##
##   {"id": "b1", "name": "Bolt", "hp": 30,
##    "stats": {"hp": 30, "attack": 6, "defense": 4, "speed": 5, "elasticity": 2, "battery_capacity": 10},
##    "skills": [{"name": "Strike", "level": 1}],
##    "personality": {"generation": 1, "aggressive": 0.4, "defensive": 0.1}}
##
## "hp" (current hp) defaults to stats.hp. Skills are looked up by name in the
## BotTuning skill catalog. "personality" holds the generation and any of the
## six ends (Personality.ENDS); left out, it comes back neutral at the
## tuning's starting generation.


static func to_dict(bot: Bot) -> Dictionary:
	var stats := {}
	for stat in Bot.STAT_NAMES:
		stats[stat] = int(bot.stats.get(stat))
	var skills := []
	for skill in bot.skills:
		skills.append({"name": skill.display_name, "level": skill.level})
	var personality := {"generation": bot.personality.generation}
	for pole in Personality.ENDS:
		if bot.personality.get_end(pole) > 0.0:
			personality[pole] = bot.personality.get_end(pole)
	return {"id": bot.id, "name": bot.display_name, "hp": bot.hp, "stats": stats, "skills": skills,
		"personality": personality}


## The bot `d` describes, or null with the reasons appended to `problems`.
static func from_dict(d: Dictionary, tuning: BotTuning, problems: Array[String]) -> Bot:
	var stats_dict: Variant = d.get("stats")
	if not stats_dict is Dictionary:
		problems.append("inline bot '%s' has no stats object" % d.get("id", ""))
		return null
	var stats := UnitStats.new()
	for stat in Bot.STAT_NAMES:
		var value: Variant = stats_dict.get(stat)
		if not (value is int or value is float):
			problems.append("inline bot '%s' is missing stat %s" % [d.get("id", ""), stat])
			return null
		stats.set(stat, int(value))
	var skills: Array[Skill] = []
	for entry: Variant in d.get("skills", []):
		var skill_name: String = entry.get("name", "") if entry is Dictionary else str(entry)
		var template := catalog_skill(tuning, skill_name)
		if template == null:
			problems.append("inline bot '%s' has unknown skill '%s'" % [d.get("id", ""), skill_name])
			return null
		var skill: Skill = template.duplicate()
		skill.level = int(entry.get("level", tuning.starting_skill_level)) if entry is Dictionary else tuning.starting_skill_level
		skills.append(skill)
	var slots: Array[AugmentSlot] = []
	for i in tuning.augment_slot_count:
		slots.append(AugmentSlot.new())
	var p_dict: Dictionary = d.get("personality", {}) if d.get("personality") is Dictionary else {}
	var personality := Personality.new(int(p_dict.get("generation", tuning.starting_generation)))
	for pole in Personality.ENDS:
		personality.set(pole, float(p_dict.get(pole, 0.0)))
	var bot := Bot.new(str(d.get("id", "")), str(d.get("name", "")), stats, personality, skills, slots)
	bot.hp = int(d.get("hp", stats.hp))
	for error in bot.validation_errors():
		problems.append(error)
	return bot if bot.is_valid() else null


## The catalog skill named `skill_name`, or null. Hand out duplicates, never this.
static func catalog_skill(tuning: BotTuning, skill_name: String) -> Skill:
	for skill in tuning.skills:
		if skill.display_name == skill_name:
			return skill
	return null
