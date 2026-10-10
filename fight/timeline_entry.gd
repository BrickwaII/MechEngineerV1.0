class_name TimelineEntry
extends RefCounted
## One upcoming action in a timeline preview. A copy: changing it changes nothing
## in the fight.

var combatant_id: String
var display_name: String
var side: Combatant.Side
## Fight tick at which the unit acts.
var tick: int
## True when this action ends a wait.
var ends_wait: bool


func _init(p_combatant_id: String, p_display_name: String, p_side: int, p_tick: int, p_ends_wait: bool) -> void:
	combatant_id = p_combatant_id
	display_name = p_display_name
	side = p_side
	tick = p_tick
	ends_wait = p_ends_wait


func _to_string() -> String:
	return "%s@%d%s" % [combatant_id, tick, " (wait)" if ends_wait else ""]
