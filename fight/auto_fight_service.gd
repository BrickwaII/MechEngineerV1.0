class_name AutoFightService
extends FightService
## A FightService that resolves each fight with the headless runner, with
## SimpleFightPolicy on both sides. Drop-in for StubFightService.
##
## The seed comes from the request unless `fixed_seed` is set, so the same
## territory and level always play out the same way. Like every FightService,
## finished is emitted on the next frame, never inside start_fight().

const NO_FIXED_SEED := -1

var fixed_seed := NO_FIXED_SEED
var tuning: CombatTuning
var enemy_table: EnemyTable
## The last fight resolved, kept for logs and debugging.
var last_fight: Fight


func _init(p_tuning: CombatTuning = null, p_enemy_table: EnemyTable = null) -> void:
	tuning = p_tuning if p_tuning != null else CombatTuning.load_default()
	enemy_table = p_enemy_table if p_enemy_table != null else EnemyTable.load_default()


func start_fight(request: FightRequest) -> void:
	var result := resolve(request)
	Engine.get_main_loop().process_frame.connect(func() -> void: finished.emit(result), CONNECT_ONE_SHOT)


## The result start_fight() will report, computed straight away.
func resolve(request: FightRequest) -> FightResult:
	last_fight = HeadlessFightRunner.run(
		request, seed_for(request), SimpleFightPolicy.new(), SimpleFightPolicy.new(), tuning, enemy_table)
	return last_fight.result()


func seed_for(request: FightRequest) -> int:
	if fixed_seed != NO_FIXED_SEED:
		return fixed_seed
	return hash("%s:%d:%d" % [request.territory_id, request.kind, request.defense_level])
