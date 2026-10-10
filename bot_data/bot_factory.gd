class_name BotFactory
extends RefCounted
## Builds randomized bots from BotTuning. The same seed always gives the same
## bots: every random draw comes from one seeded RandomNumberGenerator, never
## the global one.

var _tuning: BotTuning


func _init(tuning: BotTuning) -> void:
	_tuning = tuning


## draft_size bots, the same for the same seed. Names are not repeated.
func build_draft(seed_value: int) -> Array[Bot]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var names := _shuffled(_tuning.names, rng)
	var draft: Array[Bot] = []
	for i in _tuning.draft_size:
		draft.append(_build_bot(rng, "bot_%d" % (i + 1), names[i]))
	return draft


## A squad holding the draft from this seed. Until the draft screen exists
## (M4), the first squad_size bots are fielded.
func build_squad(seed_value: int) -> BotSquad:
	var draft := build_draft(seed_value)
	var fielded: Array[String] = []
	for i in mini(_tuning.squad_size, draft.size()):
		fielded.append(draft[i].id)
	return BotSquad.new(draft, fielded, _tuning.squad_size)


func _build_bot(rng: RandomNumberGenerator, bot_id: String, bot_name: String) -> Bot:
	var stats := UnitStats.new()
	for stat in Bot.STAT_NAMES:
		var stat_range: Vector2i = _tuning.stat_ranges[stat]
		stats.set(stat, rng.randi_range(stat_range.x, stat_range.y))

	var personality := Personality.new(_tuning.starting_generation)
	var low := _tuning.personality_start_range.x
	var high := _tuning.personality_start_range.y
	for scale in personality.get_active_scale_count():
		var value := snappedf(rng.randf_range(low, high), 0.01)
		match scale:
			Personality.Scale.AGGRESSIVE_DEFENSIVE:
				personality.aggressive_defensive = value
			Personality.Scale.SOLITARY_SUPPORTIVE:
				personality.solitary_supportive = value
			Personality.Scale.REACTIVE_METHODICAL:
				personality.reactive_methodical = value

	var skills: Array[Skill] = []
	for template in _starting_skills(_shuffled(_tuning.skills, rng)):
		var skill: Skill = template.duplicate()
		skill.level = _tuning.starting_skill_level
		skills.append(skill)

	var slots: Array[AugmentSlot] = []
	for i in _tuning.augment_slot_count:
		slots.append(AugmentSlot.new())

	return Bot.new(bot_id, bot_name, stats, personality, skills, slots)


## The catalog skills a bot starts with, from the catalog in `shuffled` order,
## by the tuning's draft rule. Draws nothing from the rng, so the rule never
## changes any other part of a draft.
func _starting_skills(shuffled: Array) -> Array:
	var picked := shuffled.slice(0, _tuning.starting_skill_count)
	if picked.is_empty() or picked.any(func(s: Skill) -> bool: return _tuning.is_guaranteed_skill(s)):
		return picked
	# Swap out the basic attack's skill when drawn (a bot fights with it anyway),
	# else the last skill.
	var slot := picked.size() - 1
	for i in picked.size():
		if (picked[i] as Skill).effect_id == _tuning.basic_attack_effect_id:
			slot = i
	for template: Skill in shuffled.slice(picked.size()):
		if _tuning.is_guaranteed_skill(template):
			picked[slot] = template
			break
	return picked


## A seeded Fisher-Yates shuffle of a copy of `items`.
static func _shuffled(items: Array, rng: RandomNumberGenerator) -> Array:
	var copy := items.duplicate()
	for i in range(copy.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var held: Variant = copy[i]
		copy[i] = copy[j]
		copy[j] = held
	return copy
