class_name StatusInstance
extends RefCounted
## One status a unit holds right now: which StatusDef, how many stacks, and who
## put it there. Lives in Combatant.statuses; StatusManager applies, consumes
## and expires it. Fight state, so Combatant.clone_for_preview() copies it.

## A StatusDef id (data/combat/statuses.json).
var status_id: String
## At least 1; never above the definition's max_stacks.
var stacks := 1
## The unit that applied it most recently.
var source_id := ""
## Fight.action_count of the action that applied it most recently.
var applied_action := 0


func _init(p_status_id := "", p_stacks := 1, p_source_id := "", p_applied_action := 0) -> void:
	status_id = p_status_id
	stacks = p_stacks
	source_id = p_source_id
	applied_action = p_applied_action


func copy() -> StatusInstance:
	return StatusInstance.new(status_id, stacks, source_id, applied_action)


func _to_string() -> String:
	return status_id if stacks == 1 else "%s x%d" % [status_id, stacks]
