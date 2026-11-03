class_name UnitIntent
extends RefCounted
## What one unit means to do next: the action, what kind of action it is, and
## how much it expects to deal or restore. A plain value; changing it changes
## nothing in the fight.

enum Kind { ATTACK, HEAL, WAIT }

var unit_id: String
var kind: Kind
var action: FightAction
## Expected damage (ATTACK), hp restored (HEAL), or damage once the wait ends (WAIT).
var amount: int
## The planner's score for this action. Higher won.
var score: float
## WAIT only: the wait is an archetype's wind-up (EnemyArchetype): the hit it
## waits for, on target_id(), is committed once the wait begins.
var wind_up := false


func _init(p_unit_id := "", p_kind := Kind.ATTACK, p_action: FightAction = null, p_amount := 0, p_score := 0.0) -> void:
	unit_id = p_unit_id
	kind = p_kind
	action = p_action
	amount = p_amount
	score = p_score


func target_id() -> String:
	return action.target_id if action != null else ""


func skill_id() -> String:
	return action.skill_id if action != null else ""


## Same kind, skill and target (and wind-up). Scores are ignored.
func same_as(other: UnitIntent) -> bool:
	if other == null:
		return false
	return (kind == other.kind and skill_id() == other.skill_id() and target_id() == other.target_id()
		and wind_up == other.wind_up)


## This intent as a wind-up: a wait for its skill on its target.
func as_wind_up() -> UnitIntent:
	var action := FightAction.wait_for(skill_id())
	action.target_id = target_id()
	var out := UnitIntent.new(unit_id, Kind.WAIT, action, amount, score)
	out.wind_up = true
	return out


func kind_name() -> String:
	return Kind.keys()[kind].to_lower()


func _to_string() -> String:
	match kind:
		Kind.WAIT:
			if wind_up:
				return "%s: wind up %s (then %s)" % [unit_id, skill_id(), target_id()]
			return "%s: wait for %s (then %s)" % [unit_id, skill_id(), target_id()]
		Kind.HEAL:
			return "%s: %s on %s (+%d)" % [unit_id, skill_id(), target_id(), amount]
	return "%s: %s on %s (%d)" % [unit_id, skill_id(), target_id(), amount]
