class_name PostFightReport
extends RefCounted
## Everything PostFight.apply() changed, for the readout screen.

## A FightResult.Outcome value.
var outcome: int = FightResult.Outcome.DEFEAT
var action_count := 0
## One per bot that fought, in roster order.
var bots: Array[BotFightReport] = []
## Why nothing was applied, or "" when the report is real.
var error := ""


func bot(bot_id: String) -> BotFightReport:
	for b in bots:
		if b.bot_id == bot_id:
			return b
	return null


func is_victory() -> bool:
	return outcome == FightResult.Outcome.VICTORY
