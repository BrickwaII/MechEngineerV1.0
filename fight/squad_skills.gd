class_name SquadSkills
extends RefCounted
## The combat skills a squad member fights with, from the skills its
## SquadMemberSummary lists. Each bot skill's effect_id picks a combat skill
## through CombatTuning.bot_skill_effects; the bot's name and level for it
## carry over. A skill whose effect has no combat skill is left out.
##
## Every member keeps CombatTuning.basic_attack: it is added, first, when the
## member's skills do not include it. A unit that cannot afford it may always
## wait, which is free. A member whose summary lists no skills, or none that
## maps to a combat skill, fights with CombatTuning.player_skills, as every member did
## before bots had skills.


## Combat skill ids for `member`, in menu order.
static func ids_for(member: SquadMemberSummary, tuning: CombatTuning) -> Array[String]:
	var ids: Array[String] = []
	if member.skills.is_empty():
		ids.assign(tuning.player_skills)
		return ids
	for entry in member.skills:
		var combat_id := tuning.combat_skill_for_effect(String(entry.get(SquadMemberSummary.SKILL_EFFECT_ID, "")))
		if combat_id.is_empty() or tuning.skill(combat_id) == null or combat_id in ids:
			continue
		ids.append(combat_id)
	if ids.is_empty():
		ids.assign(tuning.player_skills)
	elif tuning.skill(tuning.basic_attack) != null and not tuning.basic_attack in ids:
		ids.push_front(tuning.basic_attack)
	return ids


## Combat skill id -> {"name", "level"} for every skill `member` holds, for
## Combatant's skill_overrides. The basic attack added by ids_for() has none.
static func overrides_for(member: SquadMemberSummary, tuning: CombatTuning) -> Dictionary:
	var out := {}
	for entry in member.skills:
		var combat_id := tuning.combat_skill_for_effect(String(entry.get(SquadMemberSummary.SKILL_EFFECT_ID, "")))
		if combat_id.is_empty() or out.has(combat_id):
			continue
		out[combat_id] = {
			"name": String(entry.get(SquadMemberSummary.SKILL_NAME, "")),
			"level": int(entry.get(SquadMemberSummary.SKILL_LEVEL, 1)),
		}
	return out
