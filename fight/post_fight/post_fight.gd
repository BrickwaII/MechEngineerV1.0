class_name PostFight
extends RefCounted
## The one entry point after a fight ends: what each bot learned.
##
##   var report := PostFight.apply(fight, squad.get_fielded(), ledger)
##
## Reads the finished fight's decision tags, tallies personality growth and
## applies it once, counts skill uses toward skill levels (banking the rest in
## `ledger`), and returns the report the readout scene shows. A bot is matched
## to the fight by id; bots that did not fight are left alone. A fight is
## applied at most once: a second call changes nothing and reports an error.

const APPLIED_META := &"post_fight_applied"


static func apply(
	fight: Fight,
	bots: Array[Bot],
	ledger: SkillUseLedger = null,
	tuning: PostFightTuning = null,
) -> PostFightReport:
	var report := PostFightReport.new()
	if fight == null or not fight.is_over():
		report.error = "the fight is not over"
		return report
	if fight.has_meta(APPLIED_META):
		report.error = "post-fight was already applied to this fight"
		return report
	fight.set_meta(APPLIED_META, true)
	tuning = tuning if tuning != null else PostFightTuning.load_default()
	ledger = ledger if ledger != null else SkillUseLedger.new()
	report.outcome = fight.outcome
	report.action_count = fight.action_count
	for c in fight.combatants:
		if c.side != Combatant.Side.PLAYER:
			continue
		var bot := _find(bots, c.id)
		if bot != null:
			report.bots.append(_apply_to_bot(bot, fight.decision_tags, ledger, tuning, fight.tuning))
	return report


static func _apply_to_bot(bot: Bot, all_tags: Array[ActionTag], ledger: SkillUseLedger, tuning: PostFightTuning, combat: CombatTuning) -> BotFightReport:
	var r := BotFightReport.new()
	r.bot_id = bot.id
	r.display_name = bot.display_name
	for tag in all_tags:
		if tag.actor_id == bot.id:
			r.tags.append(tag)
			for label in tag.labels:
				r.label_counts[label] = r.label_counts.get(label, 0) + 1
	r.decisions = r.tags.size()
	r.generation = bot.personality.generation
	r.personality_before = PersonalityDrift.values_of(bot.personality)
	r.pole_pushes = PersonalityDrift.tally(all_tags, bot.id, tuning)
	PersonalityDrift.apply(bot.personality, PersonalityDrift.growth(r.pole_pushes, tuning))
	r.personality_after = PersonalityDrift.values_of(bot.personality)
	r.skill_changes = SkillProgress.apply(bot, SkillProgress.count_uses(all_tags, bot.id, tuning), ledger, tuning, combat)
	return r


static func _find(bots: Array[Bot], bot_id: String) -> Bot:
	for b in bots:
		if b != null and b.id == bot_id:
			return b
	return null
