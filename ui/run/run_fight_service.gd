class_name RunFightService
extends FightService
## The fight service of a run. `inner` plays each fight (FightSceneService on
## screen, AutoFightService headless); when it ends, PostFight is applied to
## the squad's bots and fight_reported is emitted, then finished passes the
## result on to the map unchanged.
##
## Variants: when each fight starts, `variants_source` gives the switchboard's
## fight-side choices (FightVariants). The fight plays with them, PostFight
## drifts personalities by their d-personality-map rule set, and HP after the
## fight follows hp-carryover (HpCarryover).
##
## Grid cost: under grid-cost-owner "fight_service", a lost attack's result
## leaves here with the defeat cost already charged (GridCostOwner), read from
## `campaign_variants_source` when the fight starts.
##
## HP between fights: TODO(decision: hp-carryover). Default: every bot heals to
## full after each fight, so a fight never changes a bot's HP.

## Emitted once per fight that had a real Fight behind it, before finished.
signal fight_reported(report: PostFightReport, result: FightResult)

var inner: FightService
var squad: BotSquad
var ledger: SkillUseLedger
## Null means data/post_fight/post_fight.json with the variants' drift rules.
var post_fight_tuning: PostFightTuning
## Returns the FightVariants each fight plays with. Defaults to the player's
## choices (FightVariants.load_active()).
var variants_source: Callable = func() -> FightVariants: return FightVariants.load_active()
## The variants the current or last fight played with.
var variants: FightVariants
## Returns the campaign variants each fight starts with (grid-cost-owner).
var campaign_variants_source: Callable = func() -> CampaignVariants: return CampaignVariants.load_active()
var _campaign_variants: CampaignVariants
var _request_kind := FightRequest.Kind.ATTACK
## The report of the last fight, or null if it had none.
var last_report: PostFightReport


func _init(p_inner: FightService, p_squad: BotSquad, p_ledger: SkillUseLedger) -> void:
	inner = p_inner
	squad = p_squad
	ledger = p_ledger
	inner.finished.connect(_on_inner_finished)


func start_fight(request: FightRequest) -> void:
	last_report = null
	variants = variants_source.call()
	_campaign_variants = campaign_variants_source.call()
	_request_kind = request.kind
	if inner.has_method("use_variants"):
		inner.use_variants(variants)
	inner.start_fight(request)


## Sets every bot's HP after `fight` by the hp-carryover variant. With no
## fight (a stub service), or the default, every bot heals to full.
func heal_squad(fight: Fight = null) -> void:
	var rule := variants if variants != null and fight != null else FightVariants.defaults()
	var end_hp := HpCarryover.end_hp_by_id(fight)
	for bot in squad.bots:
		bot.hp = HpCarryover.hp_after(end_hp.get(bot.id, bot.hp), bot.get_max_hp(), rule)


func _on_inner_finished(result: FightResult) -> void:
	# Both real services keep the fight they played; a stub has none.
	var fight := inner.get("last_fight") as Fight
	if fight != null and fight.is_over():
		var tuning := post_fight_tuning
		if tuning == null:
			tuning = PostFightTuning.for_variants(variants if variants != null else FightVariants.defaults())
		last_report = PostFight.apply(fight, squad.get_fielded(), ledger, tuning)
	heal_squad(fight if fight != null and fight.is_over() else null)
	if _campaign_variants != null:
		result = GridCostOwner.service_result(_request_kind, result, _campaign_variants)
	if last_report != null:
		fight_reported.emit(last_report, result)
	finished.emit(result)
