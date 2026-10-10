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
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("policy:%d" % seed_value)
	var actor := fight.advance()
	while actor != null:
		var policy := player_policy if actor.side == Combatant.Side.PLAYER else enemy_policy
		var action := policy.choose(fight, actor, rng)
		var problem := fight.submit(action)
		if not problem.is_empty():
			# A broken policy must not stall the fight: log it and play it safe.
			fight.log_lines.append("  policy refused (%s), %s acts by default" % [problem, actor.display_name])
			problem = fight.submit(fallback.choose(fight, actor, rng))
			assert(problem.is_empty(), problem)
		actor = fight.advance()
	return fight
