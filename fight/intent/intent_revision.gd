class_name IntentRevision
extends RefCounted
## A record that a unit changed its mind: what it meant to do, what it means to
## do now, and what in the fight changed. old_intent is null for a unit that
## had no intent; new_intent is null for a unit that no longer has one.

var unit_id: String
var old_intent: UnitIntent
var new_intent: UnitIntent
## What changed in the fight since the last plan, for example
## "Grunt 1 hp 30 -> 19". Several changes are joined with "; ".
var reason: String
## Fight action count when the revision happened.
var action_count: int


func _init(p_unit_id: String, p_old: UnitIntent, p_new: UnitIntent, p_reason: String, p_action_count: int) -> void:
	unit_id = p_unit_id
	old_intent = p_old
	new_intent = p_new
	reason = p_reason
	action_count = p_action_count


func _to_string() -> String:
	return "%s: %s -> %s because %s" % [unit_id, old_intent, new_intent, reason]
