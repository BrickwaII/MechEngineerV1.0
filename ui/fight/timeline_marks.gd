class_name TimelineMarks
extends RefCounted
## What happens at each slot of the turn order, as small icons on the
## timeline chip (combat rework S7): a status that ends when its holder next
## acts (Exposed, Brace) is marked on the holder's next slot, a Staggered
## unit's next slot is its lost turn, and a wind-up's committed hit is marked
## where it lands. Needs no scene; reads the fight it is given (the live
## fight, or a FightCopy for the order a choice would leave) and changes
## nothing.
##
##   var marks := TimelineMarks.of(fight, fight.upcoming(8))
##   # {2: [{"icon": "status_exposed", "title": "Exposed ends", "line": "..."}]}


## Slot index -> the marks on that slot, each {"icon", "title", "line"}.
## Only a unit's first slot carries marks: that is when they end or land.
static func of(fight: Fight, entries: Array[TimelineEntry], intents: Dictionary = {}) -> Dictionary:
	var out := {}
	var seen := {}
	for i in entries.size():
		var id := entries[i].combatant_id
		if seen.has(id):
			continue
		seen[id] = true
		var unit := fight.combatant(id)
		if unit == null or not unit.is_alive():
			continue
		var marks := for_unit(fight, unit, intents.get(id))
		if not marks.is_empty():
			out[i] = marks
	return out


## The marks on `unit`'s next slot. `intent` is its telegraphed intent, or
## null.
static func for_unit(fight: Fight, unit: Combatant, intent: UnitIntent = null) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if unit.staggered:
		out.append(_mark("status_staggered", "Stagger ends",
			"%s loses this turn recovering; its Plating comes back." % unit.display_name))
	for inst in unit.statuses:
		var def := fight.tuning.statuses.get_status(inst.status_id) if fight.tuning.statuses != null else null
		if def == null or def.expiry != StatusDef.EXPIRY_HOLDER_NEXT_ACTION:
			continue
		var icon := "status_%s" % inst.status_id
		if not UiIcons.has(icon):
			icon = "unknown"
		out.append(_mark(icon, "%s ends" % def.display_name,
			"%s wears off as %s acts, unless a hit uses it up first." % [def.display_name, unit.display_name]))
	if unit.brace_absorb > 0:
		out.append(_mark("status_brace", "Brace ends",
			"Brace %d ends as %s acts." % [unit.brace_absorb, unit.display_name]))
	if unit.committed != null and not unit.staggered:
		var hit := unit.skill(unit.committed.skill_id())
		var target := fight.combatant(unit.committed.target_id())
		out.append(_mark("intent_wind_up", "%s lands" % (hit.display_name if hit != null else "Hit"),
			"The wound-up %s lands on %s here, unless %s is Staggered first." % [
				hit.display_name if hit != null else "hit", target.display_name if target != null else "?", unit.display_name]))
	elif intent != null and intent.wind_up:
		var hit := unit.skill(intent.skill_id())
		out.append(_mark("intent_wind_up", "Winds up",
			"%s starts to wind up %s here; it lands at a later turn." % [unit.display_name, hit.display_name if hit != null else "a big hit"]))
	return out


static func _mark(icon: String, title: String, line: String) -> Dictionary:
	return {"icon": icon, "title": title, "line": line}
