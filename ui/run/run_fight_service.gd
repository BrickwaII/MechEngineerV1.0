class_name RunFightService
extends FightService
## The fight service of a run. `inner` plays each fight (FightSceneService on
## screen, AutoFightService headless); when it ends, PostFight is applied to
## the squad's bots and fight_reported is emitted, then finished passes the
## result on to the map unchanged.
##
## HP between fights: TODO(decision: hp-carryover). Default: every bot heals to
## full after each fight, so a fight never changes a bot's HP.

## Emitted once per fight that had a real Fight behind it, before finished.
signal fight_reported(report: PostFightReport, result: FightResult)

var inner: FightService
var squad: BotSquad
var ledger: SkillUseLedger
## Null means data/post_fight/post_fight.json.
var post_fight_tuning: PostFightTuning
## The report of the last fight, or null if it had none.
var last_report: PostFightReport


func _init(p_inner: FightService, p_squad: BotSquad, p_ledger: SkillUseLedger) -> void:
	inner = p_inner
	squad = p_squad
	ledger = p_ledger
	inner.finished.connect(_on_inner_finished)


func start_fight(request: FightRequest) -> void:
	last_report = null
	inner.start_fight(request)


## Every bot back to full HP. See the hp-carryover note above.
func heal_squad() -> void:
	for bot in squad.bots:
		bot.hp = bot.get_max_hp()


func _on_inner_finished(result: FightResult) -> void:
	# Both real services keep the fight they played; a stub has none.
	var fight := inner.get("last_fight") as Fight
	if fight != null and fight.is_over():
		last_report = PostFight.apply(fight, squad.get_fielded(), ledger, post_fight_tuning)
	heal_squad()
	if last_report != null:
		fight_reported.emit(last_report, result)
	finished.emit(result)
