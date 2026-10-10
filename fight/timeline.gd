class_name Timeline
extends RefCounted
## Turn order by gauge, in the style of an action-value system. Every tick each
## living unit adds its speed to its gauge; a unit whose gauge reaches the action
## threshold is ready. Acting spends one threshold and keeps the overflow, so a
## unit twice as fast acts twice as often.
##
## When several units are ready on the same tick, the fuller gauge goes first,
## then the higher speed, then the earlier place in the roster. No randomness.

var threshold: int
var units: Array[Combatant]
## Ticks elapsed since the fight began.
var current_tick := 0


func _init(p_units: Array[Combatant], p_threshold: int) -> void:
	units = p_units
	threshold = p_threshold


## The unit ready to act right now, or null if nobody is.
func ready_unit() -> Combatant:
	return _first_ready(units, threshold)


## Ticks until a unit is ready and returns it, or null when nobody is alive.
func advance_to_next_ready() -> Combatant:
	if not units.any(func(u: Combatant) -> bool: return u.is_alive()):
		return null
	var unit := ready_unit()
	while unit == null:
		_tick_all(units)
		current_tick += 1
		unit = ready_unit()
	return unit


## The next `count` actions in order, assuming each unit acts as soon as it is
## ready and spends no energy. Read-only: works on copies, never changes the fight.
func preview(count: int) -> Array[TimelineEntry]:
	var entries: Array[TimelineEntry] = []
	var sim: Array[Combatant] = []
	for u in units:
		sim.append(u.clone_for_preview())
	if not sim.any(func(u: Combatant) -> bool: return u.is_alive()):
		return entries
	var tick := current_tick
	while entries.size() < count:
		var unit := _first_ready(sim, threshold)
		if unit == null:
			_tick_all(sim)
			tick += 1
			continue
		entries.append(TimelineEntry.new(unit.id, unit.display_name, unit.side, tick, unit.is_waiting()))
		unit.finish_action(threshold)
	return entries


static func _tick_all(list: Array[Combatant]) -> void:
	for u in list:
		u.tick()


static func _first_ready(list: Array[Combatant], p_threshold: int) -> Combatant:
	var best: Combatant = null
	for u in list:
		if u.is_ready(p_threshold) and (best == null or _goes_before(u, best)):
			best = u
	return best


static func _goes_before(a: Combatant, b: Combatant) -> bool:
	if a.gauge != b.gauge:
		return a.gauge > b.gauge
	if a.charge_per_tick != b.charge_per_tick:
		return a.charge_per_tick > b.charge_per_tick
	return a.order < b.order
