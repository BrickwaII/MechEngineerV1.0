class_name DamageBreakdown
extends RefCounted
## One hit's damage, step by step, as DamagePipeline worked it out. Every
## field is a real value from the fight's rules, so screens explain a number
## by reading this (ui/fight/battle_math.gd) rather than redoing the math.
##
## Steps, in DamagePipeline.STEPS order:
##   attack_term     attack x power% x (100 + bonus% + speed bonus%) / 100
##   defense_term    defense x defense% x (100 - pierce%) / 100
##   floored         max(min_damage, (attack_term - defense_term) / 100)
##   after_status    floored x (100 + status_percent) / 100   (Exposed)
##   after_payoff    after_status x (100 + payoff_percent) / 100
##   before_guard    after_payoff after elasticity
##   final           before_guard after the target's guard

var attack := 0
var power_percent := 100
## Bonus from the turn: the d-wait bonus and a rank's weakest bonus.
var bonus_percent := 0
## A slow attacker's bonus (speed-range = compressed). See SpeedRules.
var speed_bonus_percent := 0
var defense := 0
var defense_percent := 0
var pierce_percent := 0
var attack_term := 0
var defense_term := 0
## attack_term - defense_term, before the division by 100 and the floor.
var raw := 0
var min_damage := 0
var floored := 0
## Extra damage the target takes from its statuses (Exposed), in percent.
var status_percent := 0
## Status ids that added status_percent, in the order the target holds them.
var status_ids: Array[String] = []
var after_status := 0
## The skill's payoff bonus when the target meets its payoff_condition, else 0.
var payoff_percent := 0
var after_payoff := 0
var before_guard := 0
var guard_percent := 0
var final := 0


## True when the floor raised the hit to min_damage.
func is_floored() -> bool:
	@warning_ignore("integer_division")
	return raw / 100 < min_damage


## True when elasticity changed the hit.
func elasticity_changed() -> bool:
	return before_guard != after_payoff
