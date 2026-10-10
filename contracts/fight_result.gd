class_name FightResult
extends RefCounted
## What a FightService reports when a fight ends. Plain data.

enum Outcome { VICTORY, DEFEAT }

## Resource ids used as keys in `rewards`.
const ENERGY := "energy"
const MATERIAL := "material"

var outcome: Outcome
## Grid capacity the fight used up, in percent of the full grid.
var grid_cost: float
## Resource id to amount gained, for example {"energy": 10}.
var rewards: Dictionary[String, int]


func _init(
	p_outcome := Outcome.DEFEAT,
	p_grid_cost := 0.0,
	p_rewards: Dictionary[String, int] = {},
) -> void:
	outcome = p_outcome
	grid_cost = p_grid_cost
	rewards = p_rewards


func is_victory() -> bool:
	return outcome == Outcome.VICTORY
