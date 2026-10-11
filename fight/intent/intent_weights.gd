class_name IntentWeights
extends RefCounted
## The hand-authored weights enemies score their options with, loaded from
## data/combat/intent/intent_weights.json.
##
## Each weight is base + sum(lean x personality lean) over the spectrums the
## unit's generation weighs (Personality.is_active), so a personality leans
## every choice it makes. A spectrum's lean is Personality.get_lean(): its two
## ends' difference scaled to -1..1 by lean_floor, so the larger end wins.
## TODO(decision: d-personality-map): the weights are first guesses.

const DEFAULT_PATH := "res://data/combat/intent/intent_weights.json"

const DAMAGE := "damage"
const ENERGY_COST := "energy_cost"
const KILL := "kill"
const HEAL := "heal"
const RETALIATE := "retaliate"
const FOCUS := "focus"
const WAIT := "wait"
const NAMES: Array[String] = [DAMAGE, ENERGY_COST, KILL, HEAL, RETALIATE, FOCUS, WAIT]

const ROLE_ATTACK := "attack"
const ROLE_HEAL := "heal"

## Scale keys in the data file, in Personality.Scale order.
const SCALE_KEYS: Array[String] = ["aggressive_defensive", "solitary_supportive", "reactive_methodical"]

## Weight name -> {base: float, leans: Array[float] in Personality.Scale order}.
var _weights: Dictionary = {}
## Skill id -> role. Skills not listed are attacks.
var _roles: Dictionary[String, String] = {}
## Personality.get_lean()'s floor: below this many points across a spectrum's
## two ends, the lean is the plain difference.
var lean_floor := 1.0


static func load_default() -> IntentWeights:
	return load_file(DEFAULT_PATH)


static func load_file(path: String) -> IntentWeights:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("IntentWeights: cannot read %s" % path)
		return null
	return from_dict(parsed)


static func from_dict(d: Dictionary) -> IntentWeights:
	var w := IntentWeights.new()
	var weights: Dictionary = d.get("weights", {})
	for name: String in weights:
		var entry: Dictionary = weights[name]
		var leans: Array[float] = []
		for key in SCALE_KEYS:
			leans.append(float(entry.get(key, 0.0)))
		w._weights[name] = {"base": float(entry.get("base", 0.0)), "leans": leans}
	w.lean_floor = float(d.get("lean_floor", 1.0))
	var roles: Dictionary = d.get("skill_roles", {})
	for id: String in roles:
		if not id.begins_with("_"):
			w._roles[id] = String(roles[id])
	return w


## The weight `name` for a unit with `personality` (null reads as balanced).
func weight(name: String, personality: Personality) -> float:
	var entry: Dictionary = _weights.get(name, {})
	if entry.is_empty():
		return 0.0
	var value: float = entry.base
	if personality != null:
		var leans: Array[float] = entry.leans
		for scale in Personality.SCALE_COUNT:
			if personality.is_active(scale):
				value += leans[scale] * personality.get_lean(scale, lean_floor)
	return value


## ROLE_ATTACK or ROLE_HEAL.
func role_of(skill_id: String) -> String:
	return _roles.get(skill_id, ROLE_ATTACK)


## Problems in the weights; empty when every weight is present and sane.
func validate() -> Array[String]:
	var problems: Array[String] = []
	for name in NAMES:
		if not _weights.has(name):
			problems.append("missing weight %s" % name)
	if lean_floor <= 0.0:
		problems.append("lean_floor must be above 0")
	for id in _roles:
		if not _roles[id] in [ROLE_ATTACK, ROLE_HEAL]:
			problems.append("skill %s has unknown role %s" % [id, _roles[id]])
	return problems
