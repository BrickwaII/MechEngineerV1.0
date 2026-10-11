class_name MapOdds
extends Node
## The odds the territory panel shows for attacking a region. Under the
## switchboard's odds-model "simulated" (default) they come from OddsEstimator
## (fight/odds/): auto-fights of the current squad against the region's own
## enemy draw, played a few at a time each frame (map.odds.frame_budget_ms in
## data/feel/screens.json) so the map never stalls. The selected region plays
## first, then every hostile region in range, so most are ready before they
## are clicked. Under "formula" the map's old stat formula
## (Campaign.odds_label()) is shown, with no percentage.

## An estimate finished for `region_id`.
signal estimated(region_id: String)

var estimator := OddsEstimator.new()
## Seeds the estimates: the same run seed, region and squad give the same odds.
var run_seed := 0
## The switchboard choices file; "" reads CampaignVariants.user_path, or the
## player's file when that is unset too.
var variants_path := ""
## Region id -> OddsEstimator.Job still playing, in play order.
var _jobs: Dictionary = {}


func _ready() -> void:
	set_process(false)


## The odds-model option in play: OddsEstimator.MODEL_SIMULATED or MODEL_FORMULA.
func model() -> String:
	var v := FightVariants.load_active(_path())
	var option := v.option(OddsEstimator.ODDS_MODEL)
	return option if not option.is_empty() else OddsEstimator.MODEL_SIMULATED


func is_simulated() -> bool:
	return model() == OddsEstimator.MODEL_SIMULATED


## Queues estimates for `selected_id` and every hostile region in range,
## selected first. Call it whenever the map or the squad may have changed.
func update(campaign: Campaign, selected_id: String) -> void:
	if campaign == null or not is_simulated():
		_jobs.clear()
		set_process(false)
		return
	estimator.use_variants(FightVariants.load_active(_path()))
	var order: Array[String] = []
	if campaign.map.has_region(selected_id) and not campaign.is_owned(selected_id):
		order.append(selected_id)
	for region in campaign.map.regions:
		if campaign.standing(region.id) == Campaign.Standing.IN_RANGE and not region.id in order:
			order.append(region.id)
	var jobs := {}
	for id in order:
		var job := _begin(campaign, id)
		var running: OddsEstimator.Job = _jobs.get(id)
		if running != null and running.key == job.key:
			job = running
		if not job.done:
			jobs[id] = job
	_jobs = jobs
	set_process(not _jobs.is_empty())


## The finished estimate for attacking `region_id`, or null while it plays.
func estimate_for(campaign: Campaign, region_id: String) -> OddsEstimator.Estimate:
	var job := _begin(campaign, region_id)
	return job.result if job.done else null


## The label to show: the estimate's band under "simulated" ("" while it
## plays), the stat formula's under "formula".
func label_for(campaign: Campaign, region_id: String) -> String:
	if not is_simulated():
		return campaign.odds_label(region_id)
	var e := estimate_for(campaign, region_id)
	return e.label if e != null else ""


## Plays every queued estimate now. Tests and screenshots use it.
func finish_all() -> void:
	while not _jobs.is_empty():
		_step(-1)


func _process(_delta: float) -> void:
	_step(int(ScreenFeel.number("map.odds.frame_budget_ms", 6.0)))


func _step(budget_msec: int) -> void:
	if _jobs.is_empty():
		set_process(false)
		return
	var id: String = _jobs.keys()[0]
	var job: OddsEstimator.Job = _jobs[id]
	if job.step(budget_msec):
		_jobs.erase(id)
		estimated.emit(id)
	set_process(not _jobs.is_empty())


func _begin(campaign: Campaign, region_id: String) -> OddsEstimator.Job:
	var region := campaign.map.get_region(region_id)
	return estimator.begin(campaign.squad_provider.get_squad(), region_id, region.defense, run_seed)


func _path() -> String:
	if not variants_path.is_empty():
		return variants_path
	return CampaignVariants.user_path if not CampaignVariants.user_path.is_empty() else FightVariants.USER_PATH
