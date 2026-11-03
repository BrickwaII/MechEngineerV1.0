class_name ResolvedScenario
extends RefCounted
## A FightScenario turned into what a fight needs. Check problems before use.

var request: FightRequest
var enemy_table: EnemyTable
var tuning: CombatTuning
var player_policy: FightPolicy
var enemy_policy: FightPolicy
## The planner archetype enemies plan their intents with (Fight.intent_planner);
## null for the fight's default. The battle debugger sets its edited one.
var intent_planner: IntentPlanner
var problems: Array[String] = []


func is_playable() -> bool:
	return problems.is_empty()


## A fight of this scenario played with `seed_value`. See SimulatedFight.
func start(seed_value: int) -> SimulatedFight:
	return SimulatedFight.new(request, seed_value, player_policy, enemy_policy, tuning, enemy_table, intent_planner)
