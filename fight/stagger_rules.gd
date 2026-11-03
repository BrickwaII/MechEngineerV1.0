class_name StaggerRules
extends RefCounted
## Plating and Stagger tuning, read from the "stagger" section of
## data/combat/combat_tuning.json (combat rework S4).
##
## A plated enemy (EnemyArchetype.plating) loses pips_per_hit pips to every
## hit it takes, or pips_per_matching_hit to a hit whose damage type matches
## its archetype's plating_weakness. At zero it is Staggered:
## - its wait (a telegraphed wind-up) and any committed hit are cancelled, its
##   intent pattern starts over (ArchetypeRules), and its next turn is spent
##   recovering instead of acting; it re-plans as it recovers
##   (TODO(decision: stagger-intent));
## - it is knocked back knockback_percent of one turn threshold on the
##   timeline (Timeline.knockback), less the d-elasticity "stagger_recovery"
##   cut;
## - every hit it takes until it recovers deals damage_bonus_percent more.
## Recovering ends the Stagger and puts back recover_percent of its plating
## (rounded down; 0 leaves it unplated for the rest of the fight).

const SECTION := "stagger"

var pips_per_hit := 1
var pips_per_matching_hit := 2
var knockback_percent := 50
var damage_bonus_percent := 50
var recover_percent := 100


## Built from the "stagger" section; keys left out take the defaults above.
static func from_dict(d: Dictionary) -> StaggerRules:
	var r := StaggerRules.new()
	r.pips_per_hit = int(d.get("pips_per_hit", r.pips_per_hit))
	r.pips_per_matching_hit = int(d.get("pips_per_matching_hit", r.pips_per_matching_hit))
	r.knockback_percent = int(d.get("knockback_percent", r.knockback_percent))
	r.damage_bonus_percent = int(d.get("damage_bonus_percent", r.damage_bonus_percent))
	r.recover_percent = int(d.get("recover_percent", r.recover_percent))
	return r


## Problems with these numbers; empty when usable.
func validate() -> Array[String]:
	var problems: Array[String] = []
	if pips_per_hit < 0:
		problems.append("stagger pips_per_hit may not be negative")
	if pips_per_matching_hit < pips_per_hit:
		problems.append("stagger pips_per_matching_hit may not be below pips_per_hit")
	if knockback_percent < 0:
		problems.append("stagger knockback_percent may not be negative")
	if damage_bonus_percent < 0:
		problems.append("stagger damage_bonus_percent may not be negative")
	if recover_percent < 0 or recover_percent > 100:
		problems.append("stagger recover_percent must be 0 to 100")
	return problems


## Pips a hit of `damage_type` strips from a unit whose plating is weak to
## `weakness` ("" is weak to nothing).
func pips_stripped(damage_type: String, weakness: String) -> int:
	if not weakness.is_empty() and damage_type == weakness:
		return pips_per_matching_hit
	return pips_per_hit


## Gauge a Stagger knocks `unit` back, on a turn threshold of `threshold`,
## after the d-elasticity "stagger_recovery" cut.
@warning_ignore("integer_division")
func knockback_gauge(unit: UnitStats, threshold: int, tuning: CombatTuning) -> int:
	var cut := ElasticityRules.stagger_knockback_cut_percent(unit, tuning)
	return maxi(0, threshold * knockback_percent / 100 * (100 - cut) / 100)


## Plating a unit with `max_plating` pips gets back when it recovers.
@warning_ignore("integer_division")
func recovered_plating(max_plating: int) -> int:
	return maxi(0, max_plating) * recover_percent / 100


## Extra damage, in percent, a hit on `target` deals.
func bonus_against(target: Combatant) -> int:
	return damage_bonus_percent if target.staggered else 0
