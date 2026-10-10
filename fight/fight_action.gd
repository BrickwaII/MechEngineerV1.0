class_name FightAction
extends RefCounted
## A decision for the unit whose turn it is: use a skill on a target, or wait.

enum Kind { SKILL, WAIT }

var kind: Kind
var skill_id: String
## Id of the target combatant. Unused for WAIT.
var target_id: String


func _init(p_kind := Kind.SKILL, p_skill_id := "", p_target_id := "") -> void:
	kind = p_kind
	skill_id = p_skill_id
	target_id = p_target_id


static func use(p_skill_id: String, p_target_id: String) -> FightAction:
	return FightAction.new(Kind.SKILL, p_skill_id, p_target_id)


## Wait until the unit can afford `p_skill_id`, then take another turn.
static func wait_for(p_skill_id: String) -> FightAction:
	return FightAction.new(Kind.WAIT, p_skill_id)


func _to_string() -> String:
	if kind == Kind.WAIT:
		return "wait for %s" % skill_id
	return "%s on %s" % [skill_id, target_id]
