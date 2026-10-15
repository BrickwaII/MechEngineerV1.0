class_name BotTuning
extends RefCounted
## The bot tuning values from data/bot_data/, read once and held as plain
## fields. No numbers live here: every value comes from the data files.

const TUNING_PATH := "res://data/bot_data/tuning.json"
const SKILLS_PATH := "res://data/bot_data/skills.json"

## Draft rules: how a drafted bot's starting skills are picked.
## Every skill is drawn at random from the catalog.
const DRAFT_RULE_RANDOM := "random"
## As random, but a bot whose draw holds no damage skill swaps its last skill
## for the first damage skill in its shuffled catalog.
const DRAFT_RULE_DAMAGE_GUARANTEE := "damage_guarantee"
## As damage_guarantee, but the damage skill may not be the basic attack every
## bot already fights with (basic_attack_effect_id, Strike). A bot without one
## swaps its Strike, else its last skill, for the first such skill in its
## shuffled catalog.
const DRAFT_RULE_NON_STRIKE_DAMAGE := "non_strike_damage"
const DRAFT_RULES: Array[String] = [DRAFT_RULE_RANDOM, DRAFT_RULE_DAMAGE_GUARANTEE, DRAFT_RULE_NON_STRIKE_DAMAGE]

var draft_size: int
var squad_size: int
var augment_slot_count: int
var starting_generation: int
var starting_skill_count: int
var starting_skill_level: int
## [low, high] for each starting personality scale value.
var personality_start_range: Vector2
## Stat name to Vector2i(low, high), both inclusive, for each of Bot.STAT_NAMES.
var stat_ranges: Dictionary[String, Vector2i] = {}
var names: Array[String] = []
## The skill catalog. Factories hand out duplicates, never these.
var skills: Array[Skill] = []
## One of DRAFT_RULES. TODO(decision: draft-rule): which rule the game keeps is
## open; data/bot_data/tuning.json picks random until it is decided.
## Data without the key drafts with the random rule.
var draft_rule := DRAFT_RULE_RANDOM
## Skill effect ids that count as damage for the damage_guarantee rule.
var damage_effect_ids: Array[String] = []
## Effect id of the basic attack every bot keeps in fights, for non_strike_damage.
var basic_attack_effect_id := ""
## Problems found while reading the files, such as a missing key.
var load_errors: PackedStringArray = []


## Reads the tuning from data/. Check is_valid() before using it.
static func load_default() -> BotTuning:
	return load_from(TUNING_PATH, SKILLS_PATH)


static func load_from(tuning_path: String, skills_path: String) -> BotTuning:
	var errors := PackedStringArray()
	var tuning_dict := _read_json(tuning_path, errors)
	var skills_dict := _read_json(skills_path, errors)
	var tuning := from_dictionaries(tuning_dict, skills_dict)
	errors.append_array(tuning.load_errors)
	tuning.load_errors = errors
	return tuning


## Builds tuning from already-parsed data, shaped like the two JSON files.
static func from_dictionaries(tuning_dict: Dictionary, skills_dict: Dictionary) -> BotTuning:
	var tuning := BotTuning.new()
	var errors := PackedStringArray()
	tuning.draft_size = _read_int(tuning_dict, "draft_size", errors)
	tuning.squad_size = _read_int(tuning_dict, "squad_size", errors)
	tuning.augment_slot_count = _read_int(tuning_dict, "augment_slot_count", errors)
	tuning.starting_generation = _read_int(tuning_dict, "starting_generation", errors)
	tuning.starting_skill_count = _read_int(tuning_dict, "starting_skill_count", errors)
	tuning.starting_skill_level = _read_int(tuning_dict, "starting_skill_level", errors)
	var range_pair := _read_pair(tuning_dict, "personality_start_range", errors)
	tuning.personality_start_range = Vector2(range_pair[0], range_pair[1])
	var ranges: Dictionary = tuning_dict.get("stat_ranges", {})
	for stat in Bot.STAT_NAMES:
		var pair := _read_pair(ranges, stat, errors, "stat_ranges.")
		tuning.stat_ranges[stat] = Vector2i(int(pair[0]), int(pair[1]))
	tuning.draft_rule = str(tuning_dict.get("draft_rule", DRAFT_RULE_RANDOM))
	tuning.basic_attack_effect_id = str(tuning_dict.get("basic_attack_effect_id", ""))
	for effect_id: Variant in tuning_dict.get("damage_effect_ids", []):
		tuning.damage_effect_ids.append(str(effect_id))
	for bot_name: Variant in tuning_dict.get("names", []):
		tuning.names.append(str(bot_name))
	for entry: Variant in skills_dict.get("skills", []):
		if entry is Dictionary:
			tuning.skills.append(Skill.new(
				str(entry.get("name", "")),
				str(entry.get("effect_id", "")),
				int(entry.get("energy_cost", -1))))
		else:
			errors.append("skills entry is not an object")
	tuning.load_errors = errors
	return tuning


## Problems with the tuning itself. Empty means a factory can use it.
func validation_errors() -> PackedStringArray:
	var errors := load_errors.duplicate()
	if squad_size <= 0:
		errors.append("squad_size must be above 0")
	if draft_size < squad_size:
		errors.append("draft_size %d is smaller than squad_size %d" % [draft_size, squad_size])
	if augment_slot_count < 0:
		errors.append("augment_slot_count is negative")
	if starting_generation < Personality.MIN_GENERATION:
		errors.append("starting_generation is below %d" % Personality.MIN_GENERATION)
	if starting_skill_level < Skill.MIN_LEVEL:
		errors.append("starting_skill_level is below %d" % Skill.MIN_LEVEL)
	if starting_skill_count < 0 or starting_skill_count > skills.size():
		errors.append("starting_skill_count %d is outside 0 to %d skills" % [starting_skill_count, skills.size()])
	if personality_start_range.x > personality_start_range.y \
			or personality_start_range.x < Personality.MIN_VALUE \
			or personality_start_range.y > Personality.MAX_VALUE:
		errors.append("personality_start_range must be low to high within -1 to 1")
	for stat in Bot.STAT_NAMES:
		var stat_range: Vector2i = stat_ranges.get(stat, Vector2i(0, -1))
		if stat_range.x < 0 or stat_range.x > stat_range.y:
			errors.append("stat range for %s must be low to high and not negative" % stat)
	if stat_ranges.get("hp", Vector2i.ZERO).x <= 0:
		errors.append("hp range must start above 0")
	if names.size() < draft_size:
		errors.append("%d names for a draft of %d" % [names.size(), draft_size])
	if not draft_rule in DRAFT_RULES:
		errors.append("draft_rule '%s' is not one of %s" % [draft_rule, ", ".join(DRAFT_RULES)])
	elif draft_rule != DRAFT_RULE_RANDOM:
		if starting_skill_count < 1:
			errors.append("draft_rule %s needs starting_skill_count of at least 1" % draft_rule)
		if not skills.any(func(s: Skill) -> bool: return is_guaranteed_skill(s)):
			errors.append("draft_rule %s has no catalog skill it can guarantee" % draft_rule)
	var skill_names := {}
	for skill in skills:
		errors.append_array(skill.validation_errors())
		if skill_names.has(skill.display_name):
			errors.append("skill '%s' is listed twice" % skill.display_name)
		skill_names[skill.display_name] = true
	return errors


func is_damage_skill(skill: Skill) -> bool:
	return skill.effect_id in damage_effect_ids


## True when `skill` satisfies the draft rule's guarantee. Always true for random.
func is_guaranteed_skill(skill: Skill) -> bool:
	match draft_rule:
		DRAFT_RULE_DAMAGE_GUARANTEE:
			return is_damage_skill(skill)
		DRAFT_RULE_NON_STRIKE_DAMAGE:
			return is_damage_skill(skill) and skill.effect_id != basic_attack_effect_id
	return true


func is_valid() -> bool:
	return validation_errors().is_empty()


## Problems with a bot measured against this tuning: its own validation, stats
## outside their ranges, and the wrong number of augment slots.
func validation_errors_for(bot: Bot) -> PackedStringArray:
	var errors := bot.validation_errors()
	if bot.stats != null:
		for stat in Bot.STAT_NAMES:
			var value := int(bot.stats.get(stat))
			var stat_range: Vector2i = stat_ranges[stat]
			if value < stat_range.x or value > stat_range.y:
				errors.append("bot '%s' %s %d is outside %d to %d" % [bot.id, stat, value, stat_range.x, stat_range.y])
	if bot.augment_slots.size() != augment_slot_count:
		errors.append("bot '%s' has %d augment slots, not %d" % [bot.id, bot.augment_slots.size(), augment_slot_count])
	return errors


static func _read_json(path: String, errors: PackedStringArray) -> Dictionary:
	if not FileAccess.file_exists(path):
		errors.append("%s does not exist" % path)
		return {}
	var parsed: Variant = JsonFile.read_object(path)
	if parsed == null:
		errors.append("%s is not a JSON object" % path)
		return {}
	return parsed


static func _read_int(dict: Dictionary, key: String, errors: PackedStringArray) -> int:
	var value: Variant = dict.get(key)
	if not (value is float or value is int):
		errors.append("%s is missing or not a number" % key)
		return 0
	return int(value)


static func _read_pair(dict: Dictionary, key: String, errors: PackedStringArray, prefix := "") -> Array[float]:
	var value: Variant = dict.get(key)
	if not value is Array or value.size() != 2 \
			or not (value[0] is float or value[0] is int) or not (value[1] is float or value[1] is int):
		errors.append("%s%s must be [low, high]" % [prefix, key])
		return [0.0, -1.0]
	return [float(value[0]), float(value[1])]
