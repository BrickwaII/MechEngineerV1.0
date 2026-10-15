class_name Stakes
extends RefCounted
## What losing costs and what Energy and Material buy (track R2-A). Numbers
## come from two data files:
##
## - The act's tuning, under "stakes" (data/tuning/overworld.json, laid over
##   by each act's file): a lost battle's cost, retreat time, the grid a
##   repair restores, how far a breach lowers defense, and fast-forward's
##   auto-reinforce.
## - The switchboard (data/variants/variants.json, F4):
##   loss-limit: lost battles per act before the run ends (0 = no limit).
##   The scaled option sets it per act: ceil(expected_fights[act] /
##   fights_per_loss), at least min_limit. TODO(decision: loss-limit).
##   Default three_per_act.
##   loss-count: all lost battles count (default), or attacks_only: a lost
##   forced defense costs the region but is not a loss (no loss count, no
##   loss cost). TODO(decision: loss-limit).
##   resource-uses: what each use costs, as {energy, material}.
##   TODO(decision: resource-uses). Default split.
##   resource-cap: capped (default) stores at most stakes.cap's base plus
##   per_region for each region held, per resource; income past it is lost,
##   and the zoom carries at most the cap. uncapped stores any amount.
##   TODO(decision: resource-cap).
##
## The uses (each cost is the resource-uses option's params):
##   reinforce  lowers pressure on a held region (also costs grid, as before)
##   retreat    backs out of a fight before it starts
##   breach     lowers the defense of the region about to be attacked
##   repair     restores grid capacity
## Under the energy-grid shared_pool variant there is no Energy stock; an
## Energy cost is paid from the pool at the variant's energy_to_pool rate.

const ENERGY := "energy"
const MATERIAL := "material"

const USE_REINFORCE := "reinforce"
const USE_RETREAT := "retreat"
const USE_BREACH := "breach"
const USE_REPAIR := "repair"
const USES: Array[String] = [USE_REINFORCE, USE_RETREAT, USE_BREACH, USE_REPAIR]

## Why a run ended, kept in RunState.ended.
const END_ALL_LOST := "all_lost"
const END_LOSS_LIMIT := "loss_limit"
const END_BOSS_LOST := "boss_lost"
const END_WON := "won"

## Lost battles per act before the run ends; 0 means no limit.
var loss_limit := 0
## False under loss-count attacks_only: a lost forced defense is no loss.
var defense_losses_count := true
## What a lost battle takes, {energy, material}.
var loss_cost: Dictionary[String, float] = {}
## Time points a retreat from an attack, and from a forced defense, costs.
var retreat_attack_time := 0
var retreat_defense_time := 0
## Grid percent a repair restores.
var repair_grid := 0.0
## Defense levels a breach takes off the attacked region.
var breach_levels := 0
## Fast-forward reinforces a held region at or above this pressure, at most
## reinforce_per_day regions a day, while it can pay.
var ff_reinforce_at := 0.0
var ff_reinforce_per_day := 0
## Resource key -> {base, per_region}; empty when the run is uncapped.
var caps: Dictionary[String, Dictionary] = {}
## Use id -> {energy, material}.
var costs: Dictionary[String, Dictionary] = {}
var errors: Array[String] = []

var _shared_pool := false
var _energy_to_pool := 0.0


## `act` (0 for act 1) picks the scaled loss limit's expected fights.
static func make(tuning: MapTuning, v: CampaignVariants, act := 0) -> Stakes:
	var s := Stakes.new()
	s._read(tuning.source.get("stakes", {}))
	s.loss_limit = loss_limit_for(v, act)
	s.defense_losses_count = not v.is_chosen(CampaignVariants.LOSS_COUNT, CampaignVariants.LOSS_COUNT_ATTACKS_ONLY)
	if not v.is_chosen(CampaignVariants.RESOURCE_CAP, CampaignVariants.CAP_UNCAPPED):
		var cap: Variant = tuning.source.get("stakes", {}).get("cap", {})
		for key in [ENERGY, MATERIAL]:
			var c: Variant = (cap as Dictionary).get(key) if cap is Dictionary else null
			if c is Dictionary:
				s.caps[key] = {"base": float(c.get("base", 0)), "per_region": float(c.get("per_region", 0))}
			else:
				s.errors.append("tuning is missing 'stakes.cap.%s'" % key)
	var p := v.params(CampaignVariants.RESOURCE_USES)
	for use in USES:
		var c: Variant = p.get(use, {})
		s.costs[use] = {
			ENERGY: float((c as Dictionary).get(ENERGY, 0)) if c is Dictionary else 0.0,
			MATERIAL: float((c as Dictionary).get(MATERIAL, 0)) if c is Dictionary else 0.0,
		}
	s._shared_pool = EnergyGridRules.is_shared(v)
	s._energy_to_pool = v.param_float(CampaignVariants.ENERGY_GRID, "energy_to_pool", 0.0)
	return s


## Lost battles act `act` allows under the loss-limit switch; 0 is no limit.
static func loss_limit_for(v: CampaignVariants, act: int) -> int:
	if not v.is_chosen(CampaignVariants.LOSS_LIMIT, CampaignVariants.LOSSES_SCALED):
		return v.param_int(CampaignVariants.LOSS_LIMIT, "limit", 0)
	var p := v.params(CampaignVariants.LOSS_LIMIT)
	var expected: Array = p.get("expected_fights", [])
	var fights := float(expected[clampi(act, 0, expected.size() - 1)]) if not expected.is_empty() else 0.0
	var per := maxf(1.0, float(p.get("fights_per_loss", 4)))
	return maxi(int(p.get("min_limit", 3)), ceili(fights / per))


func _read(d: Variant) -> void:
	if not d is Dictionary or (d as Dictionary).is_empty():
		errors.append("tuning is missing 'stakes'")
		return
	var loss: Dictionary = d.get("loss_cost", {})
	loss_cost[ENERGY] = float(loss.get(ENERGY, 0))
	loss_cost[MATERIAL] = float(loss.get(MATERIAL, 0))
	var retreat: Dictionary = d.get("retreat", {})
	retreat_attack_time = int(retreat.get("attack_time", 0))
	retreat_defense_time = int(retreat.get("defense_time", 0))
	repair_grid = float(d.get("repair_grid", 0))
	breach_levels = int(d.get("breach_levels", 0))
	var ff: Dictionary = d.get("fast_forward", {})
	ff_reinforce_at = float(ff.get("reinforce_at", 0))
	ff_reinforce_per_day = int(ff.get("reinforce_per_day", 0))


## Most of `key` the run can store while holding `held` regions; INF
## when uncapped.
func cap(key: String, held: int) -> float:
	if not caps.has(key):
		return INF
	return caps[key].base + caps[key].per_region * held


## {energy, material} a use costs.
func cost(use: String) -> Dictionary:
	return costs.get(use, {ENERGY: 0.0, MATERIAL: 0.0})


## True when the use costs anything at all; a use that costs nothing under
## the chosen option is not offered (except reinforce, which always is).
func is_offered(use: String) -> bool:
	var c := cost(use)
	return c[ENERGY] > 0.0 or c[MATERIAL] > 0.0


func can_pay(use: String, state: RunState) -> bool:
	var c := cost(use)
	return _energy_available(state) >= c[ENERGY] - 0.0001 and state.material >= c[MATERIAL] - 0.0001


## Takes a use's cost from the state. False, with nothing taken, if it
## cannot be paid.
func pay(use: String, state: RunState) -> bool:
	if not can_pay(use, state):
		return false
	var c := cost(use)
	_take_energy(state, c[ENERGY])
	state.material = maxf(0.0, state.material - c[MATERIAL])
	return true


## Takes a lost battle's cost, as much as there is.
func charge_loss(state: RunState) -> void:
	_take_energy(state, minf(loss_cost[ENERGY], _energy_available(state)))
	state.material = maxf(0.0, state.material - loss_cost[MATERIAL])


func _energy_available(state: RunState) -> float:
	if _shared_pool:
		return state.grid / _energy_to_pool if _energy_to_pool > 0.0 else 0.0
	return state.energy


func _take_energy(state: RunState, amount: float) -> void:
	if amount <= 0.0:
		return
	if _shared_pool:
		state.grid = maxf(0.0, state.grid - amount * _energy_to_pool)
	else:
		state.energy = maxf(0.0, state.energy - amount)


## "10 energy", "6 material", "4 energy + 2 material", or "free".
func cost_text(use: String) -> String:
	var c := cost(use)
	var parts := PackedStringArray()
	if c[ENERGY] > 0.0:
		parts.append("%s energy" % TextFormat.short_number(c[ENERGY]))
	if c[MATERIAL] > 0.0:
		parts.append("%s material" % TextFormat.short_number(c[MATERIAL]))
	return " + ".join(parts) if not parts.is_empty() else "free"
