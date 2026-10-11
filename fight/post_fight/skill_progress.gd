class_name SkillProgress
extends RefCounted
## Turns skill uses in a fight into skill levels; banked uses from earlier
## fights count too, and the remainder stays banked in the ledger.
##
## Named ranks (skill-progression = ranks, the default): each rank takes its
## own number of uses (uses_to_next in data/combat/skill_ranks.json), rising
## rank by rank, up to the top rank.
## Flat levels: every uses_per_level uses raise the skill by levels_per_step,
## up to max_level.
##
## A combat skill counts toward the bot skill whose effect_id it maps to in
## combat_skill_effects. A use with no matching bot skill is counted in the
## report but levels nothing.


## Uses per combat skill id from `actor_id`'s decisions, in first-use order.
## Waits are not uses.
static func count_uses(tags: Array[ActionTag], actor_id: String) -> Dictionary[String, int]:
	var uses: Dictionary[String, int] = {}
	for tag in tags:
		if tag.actor_id == actor_id and tag.kind == FightAction.Kind.SKILL:
			uses[tag.skill_id] = uses.get(tag.skill_id, 0) + 1
	return uses


## The bot's skill a combat skill counts toward, or null.
static func bot_skill_for(bot: Bot, combat_skill_id: String, tuning: PostFightTuning) -> Skill:
	var effect: String = tuning.combat_skill_effects.get(combat_skill_id, "")
	if effect.is_empty():
		return null
	for skill in bot.skills:
		if skill != null and skill.effect_id == effect:
			return skill
	return null


## Applies `uses` to `bot`'s skills and returns one change per combat skill used.
## `combat` (the fight's tuning) gives the before and after numbers; null
## leaves them out.
static func apply(bot: Bot, uses: Dictionary[String, int], ledger: SkillUseLedger, tuning: PostFightTuning, combat: CombatTuning = null) -> Array[SkillChange]:
	var changes: Array[SkillChange] = []
	for combat_id: String in uses:
		var change := SkillChange.new()
		change.combat_skill_id = combat_id
		change.uses = uses[combat_id]
		var skill := bot_skill_for(bot, combat_id, tuning)
		if skill != null:
			change.skill_name = skill.display_name
			change.max_level = tuning.top_level()
			change.level_before = skill.level
			change.banked_before = ledger.get_banked(bot.id, skill.display_name)
			var total := change.banked_before + change.uses
			if tuning.uses_ranks():
				while tuning.uses_to_next(skill.level) > 0 and total >= tuning.uses_to_next(skill.level):
					total -= tuning.uses_to_next(skill.level)
					skill.level += 1
				change.banked_after = total if tuning.uses_to_next(skill.level) > 0 else 0
			else:
				@warning_ignore("integer_division")
				var steps := total / tuning.uses_per_level
				if steps > 0:
					skill.level = maxi(skill.level, mini(tuning.max_level, skill.level + steps * tuning.levels_per_step))
				change.banked_after = total % tuning.uses_per_level
			ledger.set_banked(bot.id, skill.display_name, change.banked_after)
			change.level_after = skill.level
			change.uses_per_level = tuning.uses_to_next(skill.level) if tuning.uses_ranks() else tuning.uses_per_level
			SkillNumbers.fill(change, bot.stats, combat, tuning)
		changes.append(change)
	return changes
