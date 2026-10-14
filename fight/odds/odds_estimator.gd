class_name OddsEstimator
extends RefCounted
## Honest odds for an attack: plays `tuning.runs` headless auto-fights of the
## squad against enemies drawn by the territory's own rules (its faction under
## the enemy-factions switch, its act's tier, the defense level) and reports
## the share it won, with the label of its band (data/combat/odds.json).
##
## The policies are AutoFightService's: SimpleFightPolicy for the squad,
## IntentFightPolicy for the enemies. A person plays differently, so the rate
## is the auto-player's, not a promise.
##
## Fights are deterministic for a seed and the only chance in a fight is the
## enemy draw, so the runs differ only in the enemies drawn. Run i plays seed
## hash("odds:<run seed>:<territory>:<level>:<i>"): the estimate is the same
## for a given run seed, region and squad, and never replays the real fight's
## own seed (AutoFightService.seed_for()).
##
## Estimates are cached by squad, territory, level and run seed, so selecting
## the same region again costs nothing until the squad changes.
##
## The switchboard's odds-model decision picks this ("simulated", default) or
## the map's old stat formula ("formula", Campaign.odds_label()).

const ODDS_MODEL := FightVariants.ODDS_MODEL
const MODEL_SIMULATED := FightVariants.ODDS_SIMULATED
const MODEL_FORMULA := FightVariants.ODDS_FORMULA


## One estimate.
class Estimate:
	extends RefCounted
	var wins := 0
	var runs := 0
	var label := ""
	## Milliseconds spent playing the fights, summed over every step.
	var msec := 0

	## Wins as a share of runs, 0 to 1.
	func win_rate() -> float:
		return float(wins) / runs if runs > 0 else 0.0

	## Rounded win percent, 0 to 100.
	func percent() -> int:
		return roundi(100.0 * win_rate())


var tuning: OddsTuning
var combat_tuning: CombatTuning
var enemy_table: EnemyTable
var _cache := {}
## The auto-fight policies. Neither keeps anything between fights, so every
## fight an estimator plays shares them.
var _squad_policy := SimpleFightPolicy.new()
var _enemy_policy := IntentFightPolicy.new()


func _init(p_tuning: OddsTuning = null, p_combat_tuning: CombatTuning = null,
		p_enemy_table: EnemyTable = null) -> void:
	tuning = p_tuning if p_tuning != null else OddsTuning.load_default()
	combat_tuning = p_combat_tuning if p_combat_tuning != null else CombatTuning.load_default()
	enemy_table = p_enemy_table if p_enemy_table != null else EnemyTable.load_default()


## Plays the next estimates with `variants` (the switchboard's fight choices).
## Clears the cache when they change what a fight does.
func use_variants(variants: FightVariants) -> void:
	if variants.non_default() == combat_tuning.variants.non_default():
		return
	combat_tuning = combat_tuning.with_variants(variants)
	_cache.clear()


## The odds of `squad` attacking `territory_id` at `defense_level`, all
## fights played now.
func estimate(squad: Array[SquadMemberSummary], territory_id: String, defense_level: int,
		run_seed := 0, kind := FightRequest.Kind.ATTACK) -> Estimate:
	var job := begin(squad, territory_id, defense_level, run_seed, kind)
	job.step(-1)
	return job.result


## The cached estimate, or null when it has not been played yet.
func cached(squad: Array[SquadMemberSummary], territory_id: String, defense_level: int,
		run_seed := 0, kind := FightRequest.Kind.ATTACK) -> Estimate:
	return _cache.get(_key(squad, territory_id, defense_level, run_seed, kind))


## An estimate played a few fights at a time with Job.step(), so a screen can
## spread it over frames. A cached estimate comes back as a finished job.
func begin(squad: Array[SquadMemberSummary], territory_id: String, defense_level: int,
		run_seed := 0, kind := FightRequest.Kind.ATTACK) -> Job:
	var job := Job.new()
	job.owner = self
	job.key = _key(squad, territory_id, defense_level, run_seed, kind)
	job.request = FightRequest.new(kind, territory_id, defense_level, squad)
	job.run_seed = run_seed
	job.result = Estimate.new()
	job.result.runs = tuning.runs
	if _cache.has(job.key):
		job.result = _cache[job.key]
		job.done = true
	return job


## One estimate in progress.
class Job:
	extends RefCounted
	var owner: OddsEstimator
	var key := ""
	var request: FightRequest
	var run_seed := 0
	var result: Estimate
	var done := false
	var _next := 0

	## Plays fights until the estimate is done or `budget_msec` has passed (at
	## least one fight per call; a negative budget plays them all). Returns
	## true once done.
	func step(budget_msec: int) -> bool:
		if done:
			return true
		var started := Time.get_ticks_msec()
		while _next < result.runs:
			var fight := HeadlessFightRunner.run(request,
				OddsEstimator.seed_for(run_seed, request.territory_id, request.defense_level, _next),
				owner._squad_policy, owner._enemy_policy, owner.combat_tuning, owner.enemy_table)
			if fight.outcome == FightResult.Outcome.VICTORY:
				result.wins += 1
			_next += 1
			if budget_msec >= 0 and Time.get_ticks_msec() - started >= budget_msec:
				break
		result.msec += Time.get_ticks_msec() - started
		if _next >= result.runs:
			result.label = owner.tuning.label_for(100.0 * result.win_rate())
			owner._cache[key] = result
			done = true
		return done


func _key(squad: Array[SquadMemberSummary], territory_id: String, defense_level: int,
		run_seed: int, kind: FightRequest.Kind) -> String:
	return "%s|%s|%d|%d|%d" % [squad_key(squad), territory_id, defense_level, run_seed, kind]


static func seed_for(run_seed: int, territory_id: String, defense_level: int, i: int) -> int:
	return hash("odds:%d:%s:%d:%d" % [run_seed, territory_id, defense_level, i])


## Everything about a squad that can change a fight, as one string.
static func squad_key(squad: Array[SquadMemberSummary]) -> String:
	var parts := PackedStringArray()
	for m in squad:
		var s := m.stats
		parts.append("%s:%d/%d:%d,%d,%d,%d,%d,%d:%s" % [m.id, m.hp, m.max_hp, s.hp, s.attack, s.defense,
			s.speed, s.elasticity, s.battery_capacity, JSON.stringify(m.skills)])
	return ";".join(parts)
