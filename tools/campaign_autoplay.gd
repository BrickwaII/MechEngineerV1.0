class_name CampaignAutoplay
extends RefCounted
## Plays a whole campaign headless with a simple policy, for comparing the
## campaign variants (CampaignComparison):
##
##   1. A forced defense is fought first.
##   2. When a held region's pressure is at reinforce_at or above, reinforce
##      the one under the most pressure (file order on a tie).
##   3. Otherwise attack the weakest region in range (lowest defense, file
##      order on a tie), if the grid holds that attack's expected cost.
##   4. Otherwise wait.
##
## The run drafts its squad from the seed (BotFactory, with the squad size
## under test) and keeps it; bots do not change between fights. Act 1 starts
## where RunFlow's seeded start would. Fights play with AutoFightService at
## the fight-side defaults, each with its own seed from the run seed and the
## fight's number, so a run is the same every time for a given seed and
## variants. When an act's payload arrives the run zooms to the next act
## (ActPlan); after the last act it fights the stub boss. Every act plays its
## default map.

const ACTS_FILE := "res://data/tuning/acts.json"

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
	var provider := BotSquadProvider.new(BotFactory.new(bot_tuning()).build_squad(run_seed))
	var map := plan.load_map(0)
	var tuning := plan.load_tuning(0)
	var starts := map.start_options()
	var start: StartOption = starts[posmod(run_seed, starts.size())]
	var state := Campaign.new_run_state(map, tuning, start, run_variants)
	var c := _campaign(map, tuning, provider, state)
	while true:
		_play_act(c, r, run_seed)
		r.days_used += ceili(float(c.state.time_points) / c.tuning.points_per_day)
		if c.is_lost() or not r.problems.is_empty():
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
		if not hot.is_empty():
			c.reinforce(hot)
			continue
		var target := _weakest_in_range(c)
		if not target.is_empty() and c.state.grid >= c.attack_grid_cost(target):
			_attack(c, r, run_seed, target)
			continue
		c.wait()


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


func _attack(c: Campaign, r: Record, run_seed: int, region_id: String) -> void:
	c.set_focus(region_id)
	var request := FightRequest.new(FightRequest.Kind.ATTACK, region_id, c.map.get_region(region_id).defense,
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
	return GridCostOwner.service_result(request.kind, _service.resolve(request), fight_variants)
