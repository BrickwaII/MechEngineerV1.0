class_name SimulatedFight
extends RefCounted
## Plays a fight with policies, one decision at a time, and counts the damage
## each unit deals. Plays exactly as HeadlessFightRunner does (same policy rng,
## same fallback), so the same seed gives the same fight; the runner just does
## not expose per-unit damage, which balance tuning needs.
##
##   var sim := SimulatedFight.new(request, seed, player_policy, enemy_policy)
##   sim.run_to_end()          # or step() once per decision, e.g. for a demo
##   sim.record("my scenario") # one stats-log record

var fight: Fight
var player_policy: FightPolicy
var enemy_policy: FightPolicy
## Combatant id -> hp it has taken off opponents so far.
var damage_dealt: Dictionary[String, int] = {}

var _fallback := SimpleFightPolicy.new()
var _rng := RandomNumberGenerator.new()


func _init(
	request: FightRequest,
	seed_value: int,
	p_player_policy: FightPolicy,
	p_enemy_policy: FightPolicy = null,
	tuning: CombatTuning = null,
	enemy_table: EnemyTable = null,
) -> void:
	fight = Fight.new(request, seed_value, tuning, enemy_table)
	player_policy = p_player_policy
	enemy_policy = p_enemy_policy if p_enemy_policy != null else _fallback
	# The same policy seed HeadlessFightRunner uses.
	_rng.seed = hash("policy:%d" % seed_value)
	for c in fight.combatants:
		damage_dealt[c.id] = 0


## Plays one decision. Returns false once the fight is over.
func step() -> bool:
	var actor := fight.advance()
	if actor == null:
		return false
	var policy := player_policy if actor.side == Combatant.Side.PLAYER else enemy_policy
	var before := _opponent_hp(actor.side)
	var problem := fight.submit(policy.choose(fight, actor, _rng))
	if not problem.is_empty():
		fight.log_lines.append("  policy refused (%s), %s acts by default" % [problem, actor.display_name])
		problem = fight.submit(_fallback.choose(fight, actor, _rng))
		assert(problem.is_empty(), problem)
	damage_dealt[actor.id] += before - _opponent_hp(actor.side)
	return not fight.is_over()


func run_to_end() -> SimulatedFight:
	while step():
		pass
	return self


## One stats-log record for this fight. Only meaningful once it is over.
func record(scenario_name: String) -> Dictionary:
	var units := []
	for c in fight.combatants:
		units.append({
			"id": c.id,
			"name": c.display_name,
			"side": "player" if c.side == Combatant.Side.PLAYER else "enemy",
			"damage_dealt": damage_dealt[c.id],
			"energy_spent": float(c.energy_spent_milli) / Combatant.MILLI,
			"hp": c.hp,
			"max_hp": c.max_hp,
		})
	var result := fight.result()
	return {
		"scenario": scenario_name,
		"seed": fight.fight_seed,
		"outcome": "victory" if fight.outcome == FightResult.Outcome.VICTORY else "defeat",
		"timed_out": fight.timed_out,
		"actions": fight.action_count,
		"ticks": fight.timeline.current_tick,
		"squad_energy_spent": float(fight.energy_spent_milli(Combatant.Side.PLAYER)) / Combatant.MILLI,
		"enemy_energy_spent": float(fight.energy_spent_milli(Combatant.Side.ENEMY)) / Combatant.MILLI,
		"grid_cost": result.grid_cost,
		"units": units,
	}


func _opponent_hp(side: int) -> int:
	var total := 0
	for c in fight.combatants:
		if c.side != side:
			total += c.hp
	return total
