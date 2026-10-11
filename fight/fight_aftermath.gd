class_name FightAftermath
extends RefCounted
## What a run does to its bots when a fight ends, in one place, so the game
## (RunFightService) and the headless replay (tools/run_replay.gd) apply
## exactly the same rules:
##   1. PostFight on the fielded bots: personality drift, skill levels, uses
##      banked in the ledger. Only for a finished Fight.
##   2. Every bot's HP by the hp-carryover variant (HpCarryover). With no
##      fight (a stub service), or the default, every bot heals to full.


## Applies both steps and returns the PostFight report, or null when there was
## no finished fight. `tuning` null means data/post_fight/ with the variants'
## drift rules.
static func apply(fight: Fight, squad: BotSquad, ledger: SkillUseLedger, variants: FightVariants,
		tuning: PostFightTuning = null) -> PostFightReport:
	var report: PostFightReport = null
	var finished := fight != null and fight.is_over()
	if finished:
		if tuning == null:
			tuning = PostFightTuning.for_variants(variants if variants != null else FightVariants.defaults())
		report = PostFight.apply(fight, squad.get_fielded(), ledger, tuning)
	heal(squad, fight if finished else null, variants)
	return report


## Sets every bot's HP after `fight` by the hp-carryover variant.
static func heal(squad: BotSquad, fight: Fight, variants: FightVariants) -> void:
	var rule := variants if variants != null and fight != null else FightVariants.defaults()
	var end_hp := HpCarryover.end_hp_by_id(fight)
	for bot in squad.bots:
		bot.hp = HpCarryover.hp_after(end_hp.get(bot.id, bot.hp), bot.get_max_hp(), rule)
