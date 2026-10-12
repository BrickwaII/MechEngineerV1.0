class_name CampaignAutoplay
extends RefCounted
## Plays a whole campaign headless with a simple policy, for comparing the
## campaign variants (CampaignComparison):
##
##   1. A forced defense is fought first.
##   2. When a held region's pressure is at reinforce_at or above, reinforce
##      the one under the most pressure (file order on a tie), if the
##      reinforce cost can be paid.
##   3. Otherwise attack the weakest region in range (lowest defense, file
##      order on a tie), if the grid holds that attack's expected cost.
##   4. Otherwise wait.
##
## With `policy` POLICY_CAREFUL step 3 plays the map's odds as a person would
## (OddsEstimator, the odds the map shows): attack the in-range region with
## the best odds if they are Favored or Even; else breach the Risky region
## whose breached odds are best, when the breach can be paid; else wait.
## POLICY_BLIND (the default) is the rule above. TODO(decision: loss-limit):
## the careful rule is a stand-in for how a person picks fights.
##
## The run drafts its squad from the seed (BotFactory, with the squad size
## under test) and keeps it; bots do not change between fights unless `grow`
## is set: then every fight is applied to them (PostFight, the fight-side
## defaults), so skills rank up and personalities drift as in a real run. Act 1 starts
## where RunFlow's seeded start would. Fights play with AutoFightService at
## the fight-side defaults, each with its own seed from the run seed and the
## fight's number, so a run is the same every time for a given seed and
## variants. When an act's payload arrives the run zooms to the next act
## (ActPlan); after the last act it fights the stub boss. Every act plays its
## default map.

const ACTS_FILE := "res://data/tuning/acts.json"
const POLICY_BLIND := "blind"
const POLICY_CAREFUL := "careful"
const POLICIES: Array[String] = [POLICY_BLIND, POLICY_CAREFUL]
## Odds labels the careful policy attacks at (data/combat/odds.json bands).
const CAREFUL_ATTACK_LABELS: Array[String] = ["Favored", "Even"]
const CAREFUL_BREACH_LABELS: Array[String] = ["Risky"]

## One played campaign.
class Record:
	var run_seed := 0
	## Acts whose payload arrived with ground still held.
	var acts_cleared := 0
	## Days the run took over every act it played.
	var days_used := 0
	var fights := 0
	var forced_defenses := 0
	var attacks_won := 0
	var attacks_lost := 0
	var defenses_lost := 0
	## Regions auto-expansion took.
	var expansion_claims := 0
	## Per act played, in order: lost battles, battles fought, and the loss
	## limit that act had (0 for none).
	var losses_per_act: Array[int] = []
	var fights_per_act: Array[int] = []
	var limit_per_act: Array[int] = []
	var breaches := 0
	## Why the run ended (Stakes.END_*), or "".
	var ended := ""
	var boss_fought := false
	var boss_won := false
	## Grid percent when the run ended.
	var end_grid := 0.0
	## Actions (attack, reinforce, wait) the player chose.
	var actions := 0
	var problems: Array[String] = []


var run_variants: CampaignVariants
var fight_variants: CampaignVariants
## Pressure at which the policy reinforces.
var reinforce_at: float
## Stops an act that somehow never ends.
var max_actions_per_act: int
## POLICY_BLIND or POLICY_CAREFUL.
var policy := POLICY_BLIND
## Applies every fight to the squad's bots (PostFight) when true.
var grow := false
var _squad: BotSquad
var _ledger := SkillUseLedger.new()
var odds := OddsEstimator.new()

var _service := AutoFightService.new()
var _fight_count := 0
var _claims := 0


## `p_run_variants` are the run's next-run choices, `p_fight_variants` the
## choices each fight starts with (grid-cost-owner); null means defaults.
func _init(p_run_variants: CampaignVariants = null, p_fight_variants: CampaignVariants = null,
		settings: DevToolSettings = null) -> void:
	run_variants = p_run_variants if p_run_variants != null else CampaignVariants.defaults()
	fight_variants = p_fight_variants if p_fight_variants != null else CampaignVariants.defaults()
	if settings == null:
		settings = DevToolSettings.load_default()
	reinforce_at = settings.autoplay_reinforce_at
	max_actions_per_act = settings.autoplay_max_actions_per_act


## Plays one campaign from `run_seed`.
func play(run_seed: int) -> Record:
	var r := Record.new()
	r.run_seed = run_seed
	_fight_count = 0
	_claims = 0
	var plan := ActPlan.load_file(ACTS_FILE)
	if not plan.is_valid():
		r.problems.append_array(plan.errors)
		return r
	_squad = BotFactory.new(bot_tuning()).build_squad(run_seed)
	_ledger = SkillUseLedger.new()
	odds = OddsEstimator.new()
	var provider := BotSquadProvider.new(_squad)
	var map := plan.load_map(0)
	var tuning := plan.load_tuning(0)
	var starts := map.start_options()
	var start: StartOption = starts[posmod(run_seed, starts.size())]
	var state := Campaign.new_run_state(map, tuning, start, run_variants)
	var c := _campaign(map, tuning, provider, state)
	while true:
		var fights_before := r.fights
		_play_act(c, r, run_seed)
		r.losses_per_act.append(c.state.losses)
		r.fights_per_act.append(r.fights - fights_before)
		r.limit_per_act.append(c.stakes.loss_limit)
		r.ended = c.state.ended
		r.days_used += ceili(float(c.state.time_points) / c.tuning.points_per_day)
		if c.is_defeated() or not r.problems.is_empty():
			break
		r.acts_cleared += 1
		if not plan.has_next(c.state.act):
			_fight_boss(c, r, run_seed)
			break
		map = plan.load_map(c.state.act + 1)
		tuning = plan.load_tuning(c.state.act + 1)
		c = _campaign(map, tuning, provider, plan.zoom_state(c.state, map, tuning))
	r.end_grid = c.state.grid
	r.expansion_claims = _claims
	return r


## data/bot_data/tuning.json with the run's squad size.
func bot_tuning() -> BotTuning:
	var t := BotTuning.load_default()
	var sizes := run_variants.squad_sizes()
	if not sizes.is_empty():
		t.draft_size = sizes.draft_size
		t.squad_size = sizes.squad_size
	return t


func _campaign(map: RegionMap, tuning: MapTuning, provider: SquadProvider, state: RunState) -> Campaign:
	var c := Campaign.new(map, tuning, provider, StubFightService.new(), state)
	var fv := fight_variants
	c.next_fight_variants = func() -> CampaignVariants: return fv
	c.expanded.connect(func(_id: String) -> void: _claims += 1)
	return c


func _play_act(c: Campaign, r: Record, run_seed: int) -> void:
	var actions := 0
	while not c.is_over():
		var defense_id := c.pending_defense()
		if not defense_id.is_empty():
			_defend(c, r, run_seed, defense_id)
			continue
		if actions >= max_actions_per_act:
			r.problems.append("act %d did not end within %d actions" % [c.state.act + 1, max_actions_per_act])
			break
		actions += 1
		r.actions += 1
		var hot := _most_pressed(c)
		if not hot.is_empty() and c.reinforce(hot):
			continue
		if policy == POLICY_CAREFUL:
			if _careful_attack(c, r, run_seed):
				continue
			c.wait()
			continue
		var target := _weakest_in_range(c)
		if not target.is_empty() and c.state.grid >= c.attack_grid_cost(target):
			_attack(c, r, run_seed, target)
			continue
		c.wait()


## The careful policy's attack: true when it fought.
func _careful_attack(c: Campaign, r: Record, run_seed: int) -> bool:
	var squad := c.squad_provider.get_squad()
	var best := ""
	var best_rate := -1.0
	var breach := ""
	var breach_rate := -1.0
	for region in c.map.regions:
		if c.standing(region.id) != Campaign.Standing.IN_RANGE or c.state.grid < c.attack_grid_cost(region.id):
			continue
		var est := odds.estimate(squad, region.id, c.attack_level(region.id), run_seed)
		if est.label in CAREFUL_ATTACK_LABELS and est.win_rate() > best_rate:
			best = region.id
			best_rate = est.win_rate()
		elif est.label in CAREFUL_BREACH_LABELS and c.can_breach(region.id):
			var breached := odds.estimate(squad, region.id, c.attack_level(region.id, true), run_seed)
			if breached.win_rate() > breach_rate:
				breach = region.id
				breach_rate = breached.win_rate()
	if not best.is_empty():
		_attack(c, r, run_seed, best)
		return true
	if not breach.is_empty():
		c.stakes.pay(Stakes.USE_BREACH, c.state)
		r.breaches += 1
		_attack(c, r, run_seed, breach, true)
		return true
	return false


## The held region with the most pressure at or above reinforce_at, or "".
func _most_pressed(c: Campaign) -> String:
	var best := ""
	for region_id in c.state.owned:
		var p := c.pressure_of(region_id)
		if p >= reinforce_at and (best.is_empty() or p > c.pressure_of(best)):
			best = region_id
	return best


## The in-range region with the lowest defense, file order on a tie, or "".
func _weakest_in_range(c: Campaign) -> String:
	var best: MapRegion = null
	for region in c.map.regions:
		if c.standing(region.id) == Campaign.Standing.IN_RANGE and (best == null or region.defense < best.defense):
			best = region
	return best.id if best != null else ""


func _attack(c: Campaign, r: Record, run_seed: int, region_id: String, breach := false) -> void:
	c.set_focus(region_id)
	c.breached = breach
	var request := FightRequest.new(FightRequest.Kind.ATTACK, region_id, c.attack_level(region_id, breach),
		c.squad_provider.get_squad())
	var result := _fight(request, run_seed)
	if result.is_victory():
		r.attacks_won += 1
	else:
		r.attacks_lost += 1
	r.fights += 1
	c.apply_attack_result(region_id, result)


func _defend(c: Campaign, r: Record, run_seed: int, region_id: String) -> void:
	var attacker := c.attacker_of(region_id)
	var level := attacker.defense if attacker != null else c.tuning.uprising_defense_level
	var result := _fight(FightRequest.new(FightRequest.Kind.DEFEND, region_id, level, c.squad_provider.get_squad()), run_seed)
	r.fights += 1
	r.forced_defenses += 1
	if not result.is_victory():
		r.defenses_lost += 1
	c.apply_defense_result(region_id, result)


func _fight_boss(c: Campaign, r: Record, run_seed: int) -> void:
	var request := FightRequest.new(FightRequest.Kind.ATTACK, Campaign.BOSS_ID, c.tuning.boss_defense_level,
		c.squad_provider.get_squad())
	r.boss_fought = true
	r.boss_won = _fight(request, run_seed).is_victory()
	r.fights += 1


## Plays a fight as the run's fight service would: AutoFightService, then the
## grid-cost-owner rule on the result. Fight k of a run plays seed
## hash([run seed, k]).
func _fight(request: FightRequest, run_seed: int) -> FightResult:
	_service.fixed_seed = hash([run_seed, _fight_count]) & 0x7fffffff
	_fight_count += 1
	var result := _service.resolve(request)
	if grow:
		PostFight.apply(_service.last_fight, _squad.get_fielded(), _ledger)
	return GridCostOwner.service_result(request.kind, result, fight_variants)
