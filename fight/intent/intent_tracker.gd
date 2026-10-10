class_name IntentTracker
extends RefCounted
## Keeps every enemy's current intent and revises it when the fight changes.
##
##   var tracker := IntentTracker.new(planner)
##   tracker.refresh(fight)          # first plan, no revisions
##   fight.submit(action)
##   for r in tracker.refresh(fight):  # what changed, and why
##       print(r)
##
## refresh() is cheap to call after every submit(). It only reads the fight.

signal intent_revised(revision: IntentRevision)

var planner: IntentPlanner
## Unit id -> current UnitIntent.
var current: Dictionary[String, UnitIntent] = {}
## Every revision so far, oldest first.
var history: Array[IntentRevision] = []

## Unit id -> hp at the last refresh, to explain revisions.
var _last_hp: Dictionary[String, int] = {}
var _last_energy: Dictionary[String, int] = {}
var _planned_once := false


func _init(p_planner: IntentPlanner = null) -> void:
	planner = p_planner if p_planner != null else IntentPlanner.new()


func intent_of(unit_id: String) -> UnitIntent:
	return current.get(unit_id)


## Re-plans every enemy and returns the revisions this caused: one per unit
## whose intent changed. The first call only records the opening plan.
## `reason` overrides the reason worked out from the fight state.
func refresh(fight: Fight, reason := "") -> Array[IntentRevision]:
	var fresh := planner.plan_all(fight)
	var why := reason if not reason.is_empty() else describe_changes(fight)
	var revisions: Array[IntentRevision] = []
	if _planned_once:
		var ids: Array[String] = []
		ids.assign(current.keys())
		for id: String in fresh:
			if not id in ids:
				ids.append(id)
		for id in ids:
			var old: UnitIntent = current.get(id)
			var new: UnitIntent = fresh.get(id)
			if old == null and new == null:
				continue
			if old != null and old.same_as(new):
				continue
			revisions.append(IntentRevision.new(id, old, new, why, fight.action_count))
	current = fresh
	_planned_once = true
	_remember(fight)
	for r in revisions:
		history.append(r)
		intent_revised.emit(r)
	return revisions


## What changed in the fight since the last refresh, in roster order.
func describe_changes(fight: Fight) -> String:
	if not _planned_once:
		return "first plan"
	var parts: PackedStringArray = []
	for c in fight.combatants:
		var hp_before: int = _last_hp.get(c.id, c.hp)
		if hp_before != c.hp:
			parts.append("%s hp %d -> %d%s" % [c.display_name, hp_before, c.hp, "" if c.is_alive() else " (down)"])
	if parts.is_empty():
		for c in fight.combatants:
			var energy_before: int = _last_energy.get(c.id, c.energy())
			if energy_before != c.energy():
				parts.append("%s energy %d -> %d" % [c.display_name, energy_before, c.energy()])
	if parts.is_empty():
		return "fight state changed"
	return "; ".join(parts)


func _remember(fight: Fight) -> void:
	_last_hp.clear()
	_last_energy.clear()
	for c in fight.combatants:
		_last_hp[c.id] = c.hp
		_last_energy[c.id] = c.energy()
