class_name StubFightService
extends FightService
## Resolves a fight from its defense level alone: victory at level 3 or lower,
## defeat above. Charges 4 + 2 x defense_level percent grid either way.
## The numbers are placeholders for tests, not tuning.

const HIGHEST_WINNABLE_LEVEL := 3
const BASE_GRID_COST := 4.0
const GRID_COST_PER_LEVEL := 2.0
const VICTORY_REWARDS: Dictionary[String, int] = {FightResult.ENERGY: 10, FightResult.MATERIAL: 5}


func start_fight(request: FightRequest) -> void:
	var result := resolve(request)
	Engine.get_main_loop().process_frame.connect(func() -> void: finished.emit(result), CONNECT_ONE_SHOT)


## The result start_fight() will report, computed straight away.
func resolve(request: FightRequest) -> FightResult:
	var won := request.defense_level <= HIGHEST_WINNABLE_LEVEL
	var cost := BASE_GRID_COST + GRID_COST_PER_LEVEL * request.defense_level
	var rewards: Dictionary[String, int] = {}
	if won:
		rewards.assign(VICTORY_REWARDS)
	return FightResult.new(
		FightResult.Outcome.VICTORY if won else FightResult.Outcome.DEFEAT, cost, rewards)
