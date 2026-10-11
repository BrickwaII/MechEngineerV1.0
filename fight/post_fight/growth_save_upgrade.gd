class_name GrowthSaveUpgrade
extends RefCounted
## Brings bots from an older save up to date with the growth model.
##
## Format 1 to 2:
## - Personality: one signed value v per spectrum becomes two ends,
##   max(-v, 0) on the first and max(v, 0) on the second. Personality does
##   this itself as the file loads (its format-1 properties split on write).
## - Skills: a flat level 1 to 10 becomes a named rank, the highest rank whose
##   power is no more than the flat level's (SkillRanks.rank_for_flat_level),
##   so no skill grows stronger by the conversion.
##   TODO(decision: skill-ranks): banked uses carry over unchanged.

const FORMAT_FLAT_LEVELS := 1
## The first format with two-ended personalities and named skill ranks.
const FORMAT_GROWTH := 2


## Upgrades every bot in `squad` from `from_format`. Does nothing for a squad
## already at FORMAT_GROWTH or later.
static func upgrade_squad(squad: BotSquad, from_format: int, combat: CombatTuning = null) -> void:
	if squad == null or from_format >= FORMAT_GROWTH:
		return
	combat = combat if combat != null else CombatTuning.load_default()
	for bot in squad.bots:
		if bot != null:
			upgrade_bot(bot, combat)


## Turns `bot`'s flat skill levels into ranks.
static func upgrade_bot(bot: Bot, combat: CombatTuning) -> void:
	var ranks := combat.skill_ranks if combat.skill_ranks != null else SkillRanks.load_default()
	for skill in bot.skills:
		if skill != null:
			skill.level = ranks.rank_for_flat_level(skill.level, combat.power_percent_per_level)
