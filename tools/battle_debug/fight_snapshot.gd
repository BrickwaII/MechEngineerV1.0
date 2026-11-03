class_name FightSnapshot
extends RefCounted
## Everything a fight changes as it runs, copied at one decision point, so
## the battle debugger (S9b) can rewind to it. Restoring writes the state back
## into the same Fight and the same Combatant objects, so a screen holding
## them keeps working; only adding or removing units makes new ones.
##
##   var at_3 := FightSnapshot.capture(fight)
##   ...play on...
##   at_3.restore_into(fight)   # exactly as it was: units, timeline, log
##
## Copies every script variable of Fight and Combatant except what a fight
## shares and never changes in place (request, tuning, enemy table, the
## status table, the intent planner, each unit's skill objects and stats).
## A new piece of fight state is picked up with no change here; one that is
## changed in place and is not an Array, Dictionary or packed array needs a
## copy() and a line in _copied().
## Unit edits replace a unit's stats object rather than changing it, so a
## snapshot's shared stats stay as they were.

## Fight variables a snapshot leaves alone: shared, or handled on their own.
const FIGHT_SKIP: Array[String] = [
	"request", "fight_seed", "tuning", "enemy_table", "combatants", "timeline", "statuses",
	"intent_planner", "pending_actor",
]
## Combatant variables restored by the session, not copied (the skills come
## from the tuning in use: Combatant.refresh_skills()).
const UNIT_SKIP: Array[String] = ["_tuning", "_skills"]

## Fight.action_count when taken.
var action_count := 0
## Timeline tick when taken.
var tick := 0
## The unit the fight was waiting on, or "" for none.
var pending_id := ""
## Each unit's state, in roster order: copies, never handed out.
var units: Array[Combatant] = []
## Fight variable name -> copied value.
var fight_vars: Dictionary = {}
## Anything else the taker wants back on rewind (the debug session's policy
## rng state, its forced intents).
var extra: Dictionary = {}


static func capture(fight: Fight) -> FightSnapshot:
	var s := FightSnapshot.new()
	s.action_count = fight.action_count
	s.tick = fight.timeline.current_tick
	s.pending_id = fight.pending_actor.id if fight.pending_actor != null else ""
	for c in fight.combatants:
		s.units.append(clone_unit(c))
	for name in _script_vars(fight):
		if not name in FIGHT_SKIP:
			s.fight_vars[name] = _copied(fight.get(name))
	return s


## Ids of the units, in roster order.
func unit_ids() -> Array[String]:
	var out: Array[String] = []
	for u in units:
		out.append(u.id)
	return out


## Puts the fight back as it was when this was taken. Returns true when the
## roster changed (units were added or removed since), so the units are new
## objects; false when every unit object was kept and only its state copied.
## Call Combatant.refresh_skills() on each unit after, for the tuning in use.
func restore_into(fight: Fight) -> bool:
	var live_ids: Array[String] = []
	for c in fight.combatants:
		live_ids.append(c.id)
	var same_roster := live_ids == unit_ids()
	if same_roster:
		for i in units.size():
			copy_unit_into(units[i], fight.combatants[i])
	else:
		fight.combatants.clear()
		for u in units:
			fight.combatants.append(clone_unit(u))
	fight.timeline.units = fight.combatants
	fight.timeline.current_tick = tick
	for name: String in fight_vars:
		fight.set(name, _copied(fight_vars[name]))
	fight.pending_actor = fight.combatant(pending_id) if not pending_id.is_empty() else null
	return not same_roster


## A copy of `unit` holding every changing variable (clone_for_preview() plus
## the rest: energy spent and anything added since).
static func clone_unit(unit: Combatant) -> Combatant:
	var c := unit.clone_for_preview()
	copy_unit_into(unit, c)
	return c


## Copies every state variable of `from` onto `to` (UNIT_SKIP aside).
static func copy_unit_into(from: Combatant, to: Combatant) -> void:
	for name in _script_vars(from):
		if not name in UNIT_SKIP:
			to.set(name, _copied(from.get(name)))


## The whole fight state as plain data, for checking that two fights are in
## the same state (rewind tests, the debugger's "same as before" check).
## Units by their variables (skills by definition), the fight by its
## variables, the log as FightLog lines.
static func state_of(fight: Fight) -> Dictionary:
	var units_out := []
	for c in fight.combatants:
		var u := {}
		for name in _script_vars(c):
			if not name in UNIT_SKIP:
				u[name] = _plain(c.get(name), 0)
		var skills := {}
		for s in c.skills():
			skills[s.id] = _plain(s, 0)
		u["skills"] = skills
		units_out.append(u)
	var vars := {}
	for name in _script_vars(fight):
		if name in FIGHT_SKIP or name == "events":
			continue
		vars[name] = _plain(fight.get(name), 0)
	return {
		"tick": fight.timeline.current_tick,
		"pending": fight.pending_actor.id if fight.pending_actor != null else "",
		"units": units_out,
		"fight": vars,
		"events": Array(FightLog.lines(fight.events)),
	}


static func _script_vars(obj: Object) -> Array[String]:
	var out: Array[String] = []
	for p: Dictionary in obj.get_property_list():
		if int(p.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			out.append(String(p.name))
	return out


## A copy of a state value: containers are copied (statuses and other
## objects with copy() inside them too); objects are shared, as a fight
## never changes them in place.
static func _copied(v: Variant) -> Variant:
	match typeof(v):
		TYPE_ARRAY:
			var a: Array = (v as Array).duplicate()
			for i in a.size():
				if a[i] is StatusInstance:
					a[i] = (a[i] as StatusInstance).copy()
			return a
		TYPE_DICTIONARY:
			return (v as Dictionary).duplicate()
		TYPE_PACKED_STRING_ARRAY:
			return (v as PackedStringArray).duplicate()
		TYPE_PACKED_INT32_ARRAY:
			return (v as PackedInt32Array).duplicate()
	return v


const MAX_DEPTH := 4


static func _plain(v: Variant, depth: int) -> Variant:
	match typeof(v):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return v
		TYPE_STRING_NAME:
			return String(v)
		TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_INT32_ARRAY:
			return Array(v)
		TYPE_ARRAY:
			return (v as Array).map(func(x: Variant) -> Variant: return _plain(x, depth + 1))
		TYPE_DICTIONARY:
			var out := {}
			for k: Variant in v:
				out[str(k)] = _plain(v[k], depth + 1)
			return out
		TYPE_OBJECT:
			if v == null:
				return null
			if v is UnitStats:
				var st := v as UnitStats
				return [st.hp, st.attack, st.defense, st.speed, st.elasticity, st.battery_capacity]
			if v is EnemyArchetype:
				return "archetype:" + (v as EnemyArchetype).id
			if v is Combatant:
				return "unit:" + (v as Combatant).id
			if v is CombatTuning or v is EnemyTable or v is IntentPlanner or v is Fight:
				return "<shared>"
			if depth >= MAX_DEPTH:
				return str(v)
			var out := {}
			for name in _script_vars(v):
				out[name] = _plain((v as Object).get(name), depth + 1)
			return out
	return str(v)
