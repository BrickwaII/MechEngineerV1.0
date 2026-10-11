class_name Campaign
extends RefCounted
## The overworld rules: who holds what, time, pressure, grid capacity, and the
## fights they lead to. Needs no scene, so it runs headless in tests.
##
## Fights go only through the contracts: the squad comes from a SquadProvider
## and each fight from a FightService. Any implementation of those two works
## here unchanged.
##
## Variants (campaign/variants/): the run's next-run choices are kept in
## state.variants and read into `variants` here; act pacing replaces `tuning`
## with the act's paced copy, energy-grid and auto-expansion change how time
## passes. grid-cost-owner is read when each fight starts, from
## next_fight_variants.

signal changed
## The player chose a map action that needs no fight: WAIT, or REINFORCE on
## `region_id`. Emitted before the action changes anything.
signal acted(action: Action, region_id: String)
signal event_logged(text: String)
signal fight_started(request: FightRequest)
signal fight_finished(request: FightRequest, result: FightResult)
## A region auto-expansion took without a fight.
signal expanded(region_id: String)

## How a region looks from the player's side.
enum Standing { OWNED, IN_RANGE, OUT_OF_REACH }
enum Action { NONE, ATTACK, REINFORCE, WAIT }
## Why pressure builds on a held region.
enum Cause { UPRISING, ATTACK }

## The territory id the stub boss fight is fought over.
const BOSS_ID := "boss"

var map: RegionMap
var tuning: MapTuning
var state: RunState
var squad_provider: SquadProvider
var fight_service: FightService
## True while a fight is out with the FightService.
var fighting := false
## The run's campaign variants, from state.variants.
var variants: CampaignVariants
## Gives the campaign variants a fight starts with (grid-cost-owner). Defaults
## to the player's choices (CampaignVariants.load_active()).
var next_fight_variants: Callable = func() -> CampaignVariants: return CampaignVariants.load_active()
## The variants of the fight in progress, or null between fights.
var _fight_variants: CampaignVariants


func _init(
	p_map: RegionMap,
	p_tuning: MapTuning,
	p_squad_provider: SquadProvider,
	p_fight_service: FightService,
	p_state: RunState = null,
) -> void:
	map = p_map
	squad_provider = p_squad_provider
	fight_service = p_fight_service
	state = p_state if p_state != null else new_run_state(p_map, p_tuning)
	variants = CampaignVariants.for_run(state.variants)
	tuning = ActPacing.paced(p_tuning, state.act, variants)


## The state a fresh run starts from. `start` is one of the map's
## start_options(); null takes the first. `run_variants` are the switchboard
## choices the run keeps; null reads CampaignVariants.load_active().
static func new_run_state(p_map: RegionMap, p_tuning: MapTuning, start: StartOption = null,
		run_variants: CampaignVariants = null) -> RunState:
	if start == null:
		start = p_map.get_start("")
	if run_variants == null:
		run_variants = CampaignVariants.load_active()
	p_tuning = ActPacing.paced(p_tuning, 0, run_variants)
	var s := RunState.new()
	s.variants = run_variants.run_choices()
	s.region_set_id = p_map.id
	s.act = 0
	s.start_id = start.id
	s.owned = _in_file_order(p_map, start.regions)
	for region_id in s.owned:
		s.pressure[region_id] = p_tuning.start_pressure
		if start.pressure_rate_factor != 1.0:
			s.pressure_rate_factor[region_id] = start.pressure_rate_factor
	for key in MapRegion.RESOURCE_KEYS:
		s.income_bonus[key] = start.income_bonus.get(key, 0)
	s.energy = p_tuning.start_energy + start.energy
	s.material = p_tuning.start_material + start.material
	s.time_points = 0
	s.grid = p_tuning.start_grid
	EnergyGridRules.start(s, p_tuning, run_variants)
	return s


## These region ids, sorted into the map's file order.
static func _in_file_order(p_map: RegionMap, region_ids: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for region_id in p_map.ids():
		if region_id in region_ids:
			out.append(region_id)
	return out


# --- Questions about the map -------------------------------------------------

func is_owned(region_id: String) -> bool:
	return region_id in state.owned


func standing(region_id: String) -> Standing:
	if is_owned(region_id):
		return Standing.OWNED
	for other_id in map.get_region(region_id).adjacent:
		if is_owned(other_id):
			return Standing.IN_RANGE
	return Standing.OUT_OF_REACH


## A held region with at least one hostile neighbor.
func is_border(region_id: String) -> bool:
	for other_id in map.get_region(region_id).adjacent:
		if not is_owned(other_id):
			return true
	return false


func pressure_of(region_id: String) -> float:
	return state.pressure.get(region_id, 0.0)


## Pressure a held region gains per time point.
func pressure_rate(region_id: String) -> float:
	var region := map.get_region(region_id)
	var rate := tuning.pressure_rate_base + tuning.pressure_rate_per_base * region.pressure_base
	if is_border(region_id):
		rate *= tuning.border_multiplier
	return rate * pressure_scale() * state.pressure_rate_factor.get(region_id, 1.0)


## The act's factor on every pressure rate: the tuning's scale, times its
## reference region count over this map's when it gives one.
func pressure_scale() -> float:
	var scale := tuning.pressure_scale
	if tuning.pressure_reference_regions > 0:
		scale *= float(tuning.pressure_reference_regions) / map.regions.size()
	return scale


## The hostile neighbor pressing on a held region: the best defended one, the
## first in file order on a tie. Null when every neighbor is held, which makes
## the cause an uprising.
func attacker_of(region_id: String) -> MapRegion:
	var best: MapRegion = null
	for other_id in map.get_region(region_id).adjacent:
		if is_owned(other_id):
			continue
		var other := map.get_region(other_id)
		if best == null or other.defense > best.defense:
			best = other
	return best


func cause_of(region_id: String) -> Cause:
	return Cause.ATTACK if attacker_of(region_id) != null else Cause.UPRISING


## Per-day totals of what the held regions provide, plus the starting
## location's bonus, keyed like MapRegion.provides.
func income_per_day() -> Dictionary[String, int]:
	var total: Dictionary[String, int] = {}
	for key in MapRegion.RESOURCE_KEYS:
		total[key] = state.income_bonus.get(key, 0)
	for region_id in state.owned:
		var region := map.get_region(region_id)
		for key in MapRegion.RESOURCE_KEYS:
			total[key] += region.provides[key]
	return total


## Grid percent an attack on this region is expected to cost if it wins.
func attack_grid_cost(region_id: String) -> float:
	return tuning.attack_grid_base + tuning.attack_grid_per_defense * map.get_region(region_id).defense


## Squad strength as a defense level, from the fielded squad's stats.
## TODO(decision: odds-model): a placeholder until real fights can be simulated.
func squad_level() -> int:
	var points := 0
	for member in squad_provider.get_squad():
		points += member.stats.attack + member.stats.defense
	return points / tuning.squad_stat_points_per_level


## The odds label for attacking a region, such as "Favored".
func odds_label(region_id: String) -> String:
	var margin := squad_level() - map.get_region(region_id).defense
	for band in tuning.odds_bands:
		if margin >= band["min_margin"]:
			return band["label"]
	return tuning.odds_bands[-1]["label"] if not tuning.odds_bands.is_empty() else ""


# --- Time ---------------------------------------------------------------------

## Day number, starting at 1.
func day() -> int:
	var days := tuning.total_points / tuning.points_per_day
	return mini(days, state.time_points / tuning.points_per_day + 1)


func days_left() -> int:
	return ceili(float(tuning.total_points - state.time_points) / tuning.points_per_day)


func time_cost(action: Action) -> int:
	match action:
		Action.ATTACK:
			return tuning.attack_time
		Action.REINFORCE:
			return tuning.reinforce_time
		Action.WAIT:
			return tuning.wait_time
	return 0


## Grid percent an action is expected to cost. For an attack this is the cost
## on victory; a defeat costs more.
func grid_cost(action: Action, region_id := "") -> float:
	match action:
		Action.ATTACK:
			return attack_grid_cost(region_id)
		Action.REINFORCE:
			return tuning.reinforce_grid_cost
	return 0.0


## The action the panel would offer for a region: attack a hostile region in
## range, reinforce a held one, nothing otherwise.
func action_for(region_id: String) -> Action:
	match standing(region_id):
		Standing.OWNED:
			return Action.REINFORCE
		Standing.IN_RANGE:
			return Action.ATTACK
	return Action.NONE


# --- Run status ---------------------------------------------------------------

## True once the countdown has run out. The boss fight then starts.
func is_payload_due() -> bool:
	return state.time_points >= tuning.total_points


func is_lost() -> bool:
	return state.owned.is_empty()


func is_over() -> bool:
	return is_payload_due() or is_lost()


## A held region whose pressure is full and must be defended before anything
## else happens, or "" if none.
func pending_defense() -> String:
	for region_id in state.owned:
		if pressure_of(region_id) >= tuning.forces_defense_at:
			return region_id
	return ""


## True when the player may choose an action.
func can_act() -> bool:
	return not fighting and not is_over() and pending_defense().is_empty()


func can_attack(region_id: String) -> bool:
	# TODO(decision: grid-empty): the mockup lets an attack go ahead on an empty
	# grid and clamps at 0; a low grid does not block anything yet.
	return can_act() and map.has_region(region_id) and standing(region_id) == Standing.IN_RANGE


func can_reinforce(region_id: String) -> bool:
	return can_act() and is_owned(region_id)


# --- Actions --------------------------------------------------------------------

func wait() -> bool:
	if not can_act():
		return false
	acted.emit(Action.WAIT, "")
	_advance(tuning.wait_time)
	changed.emit()
	return true


func reinforce(region_id: String) -> bool:
	if not can_reinforce(region_id):
		return false
	acted.emit(Action.REINFORCE, region_id)
	state.pressure[region_id] = maxf(0.0, pressure_of(region_id) - tuning.reinforce_relief)
	state.grid = maxf(0.0, state.grid - tuning.reinforce_grid_cost)
	_log("Reinforced %s." % map.get_region(region_id).name)
	_advance(tuning.reinforce_time)
	changed.emit()
	return true


## Attacks a hostile region in range through the FightService. Returns false
## without fighting if the attack is not allowed. Await it.
func attack(region_id: String) -> bool:
	if not can_attack(region_id):
		return false
	var region := map.get_region(region_id)
	set_focus(region_id)
	var request := FightRequest.new(
		FightRequest.Kind.ATTACK, region_id, region.defense, squad_provider.get_squad())
	var result := await _run_fight(request)
	if result == null:
		return false
	apply_attack_result(region_id, result)
	return true


## Fights the defensive battle pending_defense() names. Returns false if none
## is pending. Await it.
func defend() -> bool:
	var region_id := pending_defense()
	if region_id.is_empty() or fighting or is_over():
		return false
	var attacker := attacker_of(region_id)
	var level := attacker.defense if attacker != null else tuning.uprising_defense_level
	var request := FightRequest.new(
		FightRequest.Kind.DEFEND, region_id, level, squad_provider.get_squad())
	var result := await _run_fight(request)
	if result == null:
		return false
	apply_defense_result(region_id, result)
	return true


## The boss fight at the last act's payload, through the FightService like any
## other fight. Returns the result, or null if the payload is not due or a
## fight is already out. Await it. The run ends either way; the caller says how.
## TODO(decision: boss-fight): a stub. It is an attack on territory BOSS_ID at
## the tuning's boss.defense_level until the boss fight is designed.
func boss_fight() -> FightResult:
	if not is_payload_due() or fighting or is_lost():
		return null
	var request := FightRequest.new(
		FightRequest.Kind.ATTACK, BOSS_ID, tuning.boss_defense_level, squad_provider.get_squad())
	var result := await _run_fight(request)
	if result != null:
		_log("The boss is beaten." if result.is_victory() else "The boss holds.")
		changed.emit()
	return result


## Grid percent a finished fight takes from the grid.
## TODO(decision: grid-cost-owner): by default StubFightService charges the
## same on victory and defeat, so the map applies the defeat multiplier
## itself; see GridCostOwner for the other options.
func fight_grid_charge(kind: FightRequest.Kind, result: FightResult) -> float:
	var v := _fight_variants if _fight_variants != null else next_fight_variants.call() as CampaignVariants
	return GridCostOwner.map_charge(kind, result, v, tuning.defeat_grid_multiplier)


## Makes `region_id` the player's focus, which auto-expansion leans toward.
## Attacking a region makes it the focus; the map screen may call this when
## a region is selected.
func set_focus(region_id: String) -> void:
	if map.has_region(region_id):
		state.focus_id = region_id


## Applies a finished attack: capture on victory, grid cost, rewards, time.
func apply_attack_result(region_id: String, result: FightResult) -> void:
	var region := map.get_region(region_id)
	if result.is_victory():
		_set_owned(region_id, true)
		state.pressure[region_id] = tuning.pressure_after_capture
		_log("Captured %s." % region.name)
	else:
		_log("The assault on %s was repelled." % region.name)
	state.grid = maxf(0.0, state.grid - fight_grid_charge(FightRequest.Kind.ATTACK, result))
	_end_fight_variants()
	_add_rewards(result)
	_advance(tuning.attack_time)
	changed.emit()


## Applies a finished defensive fight: pressure eases on victory, the region is
## lost on defeat. Takes no time; the fight was forced.
func apply_defense_result(region_id: String, result: FightResult) -> void:
	var region := map.get_region(region_id)
	if result.is_victory():
		state.pressure[region_id] = tuning.pressure_after_defense_victory
		_log("Held %s." % region.name)
	else:
		_set_owned(region_id, false)
		_log("Lost %s. It is hostile again." % region.name)
	state.grid = maxf(0.0, state.grid - fight_grid_charge(FightRequest.Kind.DEFEND, result))
	_end_fight_variants()
	_add_rewards(result)
	changed.emit()


## Moves time forward point by point: pressure builds, resources and grid accrue.
## Stops at the end of the countdown.
func _advance(points: int) -> void:
	var was_due := is_payload_due()
	for i in points:
		if is_payload_due():
			break
		var income := income_per_day()
		var rates := {}
		for region_id in state.owned:
			rates[region_id] = pressure_rate(region_id)
		for region_id in state.owned:
			state.pressure[region_id] = minf(tuning.forces_defense_at, pressure_of(region_id) + rates[region_id])
		EnergyGridRules.accrue_point(state, income, tuning, variants)
		state.material += float(income[MapRegion.MATERIAL]) / tuning.points_per_day
		state.time_points += 1
		if state.time_points % tuning.points_per_day == 0:
			_expand()
	var defense_id := pending_defense()
	if not defense_id.is_empty():
		var attacker := attacker_of(defense_id)
		var region_name := map.get_region(defense_id).name
		_log("%s is under attack from %s." % [region_name, attacker.name] if attacker != null
			else "%s has risen in revolt." % region_name)
	if is_payload_due() and not was_due:
		_log("The payload has arrived.")


func _run_fight(request: FightRequest) -> FightResult:
	if not request.is_valid():
		push_error("Campaign: not starting an invalid fight for '%s'" % request.territory_id)
		return null
	fighting = true
	_fight_variants = next_fight_variants.call()
	changed.emit()
	fight_started.emit(request)
	fight_service.start_fight(request)
	var result: FightResult = await fight_service.finished
	fighting = false
	fight_finished.emit(request, result)
	return result


## Clears the fight-start variants once a fight's result is applied.
func _end_fight_variants() -> void:
	_fight_variants = null


## A day of auto-expansion, when the run has it on in this act.
func _expand() -> void:
	if not AutoExpansion.is_on(variants, state.act):
		return
	for region_id in AutoExpansion.advance_day(map, state, variants):
		_set_owned(region_id, true)
		state.pressure[region_id] = tuning.pressure_after_capture
		_log("%s went over to your side." % map.get_region(region_id).name)
		expanded.emit(region_id)


func _set_owned(region_id: String, held: bool) -> void:
	var owned := PackedStringArray()
	for other_id in map.ids():
		if other_id == region_id:
			if held:
				owned.append(other_id)
		elif is_owned(other_id):
			owned.append(other_id)
	state.owned = owned
	if not held:
		state.pressure.erase(region_id)


func _add_rewards(result: FightResult) -> void:
	EnergyGridRules.add_energy(state, result.rewards.get(FightResult.ENERGY, 0), tuning, variants)
	state.material += result.rewards.get(FightResult.MATERIAL, 0)


func _log(text: String) -> void:
	event_logged.emit(text)
