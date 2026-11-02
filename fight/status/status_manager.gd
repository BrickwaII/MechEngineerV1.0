class_name StatusManager
extends RefCounted
## Applies, consumes and expires statuses (StatusDef) on the units of a fight.
## The state lives on each Combatant (Combatant.statuses), so copying the units
## copies it; this object holds only the definitions and the rules.
##
## Driven by timeline events, through three calls:
##   apply(unit, id, ...)        an action puts a status on its target
##   on_unit_acts(unit)          the unit begins an action (a skill or a wait):
##                               its holder_next_action statuses end
##   consume_after_hit(...)      a damage hit landed: statuses consumed by a hit
##                               (and by the action's payoff) are used up
## Each returns what changed so the fight can raise FightEvents and log lines.
## Fight calls on_unit_acts() when it resolves a decision; S2's timeline can
## call it from its own next-action event instead, with nothing else changing.
##
## Wait state (Charging, Waiting) is timeline state on Combatant, not a status
## (combat-rework-map C9). Guard stays Combatant.guard_percent until S11
## (combat-rework-questions row 6).
##
## What a status does to damage is read by DamagePipeline through
## damage_taken_percent() and holds(); nothing else in a fight reads statuses.

var table: StatusTable


func _init(p_table: StatusTable = null) -> void:
	table = p_table if p_table != null else StatusTable.load_default()


## Puts status `status_id` on `unit`, or adds a stack (up to max_stacks; at
## the cap it only refreshes the source). Returns the instance it holds now,
## or null for an unknown status or a downed unit.
func apply(unit: Combatant, status_id: String, source_id := "", action_index := 0) -> StatusInstance:
	var def := table.get_status(status_id)
	if def == null or not unit.is_alive():
		return null
	var held := unit.status(status_id)
	if held == null:
		held = StatusInstance.new(status_id, 1, source_id, action_index)
		unit.statuses.append(held)
	else:
		held.stacks = mini(def.max_stacks, held.stacks + 1)
		held.source_id = source_id
		held.applied_action = action_index
	return held


## The unit begins an action: removes and returns its statuses that last until
## the holder's next action. Call it before the action changes anything.
func on_unit_acts(unit: Combatant) -> Array[StatusInstance]:
	return _remove(unit, func(def: StatusDef) -> bool:
		return def.expiry == StatusDef.EXPIRY_HOLDER_NEXT_ACTION)


## A damage hit from `skill` landed on `unit`: removes and returns the
## statuses that hit uses up. A status consumed by `hit` always goes; one
## consumed by `payoff` goes when the skill's payoff_condition names it.
func consume_after_hit(unit: Combatant, skill: CombatSkill) -> Array[StatusInstance]:
	return _remove(unit, func(def: StatusDef) -> bool:
		return def.is_consumed_by(StatusDef.CONSUMED_BY_HIT) \
			or (def.is_consumed_by(StatusDef.CONSUMED_BY_PAYOFF) and skill.payoff_condition == def.id))


## Extra damage `unit` takes, in percent, from its damage_taken_percent
## statuses (Exposed): amount x stacks, summed. 0 with none.
func damage_taken_percent(unit: Combatant) -> int:
	return damage_taken_percent_of(unit, table)


## The same, for callers that hold only a table (DamagePipeline).
static func damage_taken_percent_of(unit: Combatant, p_table: StatusTable) -> int:
	var total := 0
	if p_table == null:
		return total
	for s in unit.statuses:
		var def := p_table.get_status(s.status_id)
		if def != null and def.effect == StatusDef.EFFECT_DAMAGE_TAKEN_PERCENT:
			total += def.amount * s.stacks
	return total


## Display name of status `status_id`, or the id when it is not defined.
func name_of(status_id: String) -> String:
	var def := table.get_status(status_id)
	return def.display_name if def != null else status_id


func _remove(unit: Combatant, matches: Callable) -> Array[StatusInstance]:
	var gone: Array[StatusInstance] = []
	var kept: Array[StatusInstance] = []
	for s in unit.statuses:
		var def := table.get_status(s.status_id)
		if def != null and matches.call(def):
			gone.append(s)
		else:
			kept.append(s)
	unit.statuses = kept
	return gone
