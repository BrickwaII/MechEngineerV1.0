class_name CombatSkill
extends RefCounted
## One combat skill: a flat energy cost and a power multiplier. Plain data,
## read from data/combat/combat_tuning.json. A damage skill hits an opponent;
## a heal skill restores hp to a living ally (the user included).

const EFFECT_DAMAGE := "damage"
const EFFECT_HEAL := "heal"

var id: String
var display_name: String
## Whole energy points spent when the skill is used.
var energy_cost: int
## Damage before defense (or hp restored), in percent of the user's attack.
var power_percent: int
## EFFECT_DAMAGE or EFFECT_HEAL.
var effect: String


func _init(p_id := "", p_display_name := "", p_energy_cost := 0, p_power_percent := 100, p_effect := EFFECT_DAMAGE) -> void:
	id = p_id
	display_name = p_display_name
	energy_cost = p_energy_cost
	power_percent = p_power_percent
	effect = p_effect


func is_heal() -> bool:
	return effect == EFFECT_HEAL


func energy_cost_milli() -> int:
	return energy_cost * Combatant.MILLI
