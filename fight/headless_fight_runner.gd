class_name HeadlessFightRunner
extends RefCounted
## Plays a whole fight with no scene: policies make every decision. The same
## request, seed and policies give the same fight and the same log, every time.


## Runs the fight to its end and returns it; read result() and log_text().
## `enemy_policy` defaults to SimpleFightPolicy. Policies draw from their own
## rng, seeded from `seed`, so a random policy replays exactly.
static func run(
	request: FightRequest,
	seed_value: int,
	player_policy: FightPolicy,
	enemy_policy: FightPolicy = null,
	tuning: CombatTuning = null,
	enemy_table: EnemyTable = null,
) -> Fight:
	var fight := Fight.new(request, seed_value, tuning, enemy_table)
	var fallback := SimpleFightPolicy.new()
	if enemy_policy == null:
		enemy_policy = fallback
	var rng := policy_rng(seed_value)
	var actor := fight.advance()
	while actor != null:
		play_turn(fight, actor, player_policy if actor.side == Combatant.Side.PLAYER else enemy_policy, fallback, rng)
		actor = fight.advance()
	return fight


## The rng policies draw from in the fight with `seed_value`. Every player of
## a fight seeds it this way, so a policy that draws replays exactly.
static func policy_rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("policy:%d" % seed_value)
	return rng


## Submits `policy`'s choice for `actor`, the unit the fight waits on. A
## broken policy must not stall the fight: a refused action is logged and
## `fallback` plays the turn instead.
static func play_turn(fight: Fight, actor: Combatant, policy: FightPolicy, fallback: FightPolicy,
		rng: RandomNumberGenerator) -> void:
	var problem := fight.submit(policy.choose(fight, actor, rng))
	if not problem.is_empty():
		fight.log_lines.append("  policy refused (%s), %s acts by default" % [problem, actor.display_name])
		problem = fight.submit(fallback.choose(fight, actor, rng))
		assert(problem.is_empty(), problem)
