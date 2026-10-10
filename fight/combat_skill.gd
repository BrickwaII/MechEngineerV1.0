class_name CombatSkill
extends RefCounted
## One combat skill: a flat energy cost and a damage multiplier. Plain data,
## read from data/combat/combat_tuning.json.

var id: String
var display_name: String
## Whole energy points spent when the skill is used.
var energy_cost: int
## Damage before defense, in percent of the user's attack.
var power_percent: int


func _init(p_id := "", p_display_name := "", p_energy_cost := 0, p_power_percent := 100) -> void:
	id = p_id
	display_name = p_display_name
	energy_cost = p_energy_cost
	power_percent = p_power_percent


func energy_cost_milli() -> int:
	return energy_cost * Combatant.MILLI
