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


## The shipped file; read from disk once, a fresh object every call.
static func load_default() -> IntentWeights:
	var d: Variant = JsonFile.read_object_cached(DEFAULT_PATH)
	return from_dict(d) if d != null else load_file(DEFAULT_PATH)


static func load_file(path: String) -> IntentWeights:
	var d: Variant = JsonFile.read_object(path)
	if d == null:
		push_error("IntentWeights: cannot read %s" % path)
		return null
	return from_dict(d)


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


## Every weight in NAMES for a unit with `personality`, by name: what
## weight() gives, worked out once for a unit's whole set of options.
func weights_for(personality: Personality) -> Dictionary[String, float]:
	var out: Dictionary[String, float] = {}
	for name in NAMES:
		out[name] = weight(name, personality)
	return out


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


## The keys of one weight's numbers as the data file has them: "base", then
## each SCALE_KEYS lean.
static func value_keys() -> Array[String]:
	var out: Array[String] = ["base"]
	out.append_array(SCALE_KEYS)
	return out


## Weight `name`'s number under `key` (a value_keys() entry), as in the data
## file: its base, or its lean on one spectrum. 0 when not set.
func value(name: String, key: String) -> float:
	var entry: Dictionary = _weights.get(name, {})
	if entry.is_empty():
		return 0.0
	if key == "base":
		return float(entry.base)
	var scale := SCALE_KEYS.find(key)
	return float(entry.leans[scale]) if scale >= 0 else 0.0


## Sets weight `name`'s number under `key` (a value_keys() entry), adding
## the weight when it is missing. For dev tools that tune live (the battle
## debugger, S9b); fights never change their weights.
func set_value(name: String, key: String, v: float) -> void:
	if not _weights.has(name):
		var zeros: Array[float] = []
		for _scale in SCALE_KEYS:
			zeros.append(0.0)
		_weights[name] = {"base": 0.0, "leans": zeros}
	if key == "base":
		_weights[name].base = v
		return
	var scale := SCALE_KEYS.find(key)
	if scale >= 0:
		var leans: Array[float] = _weights[name].leans
		leans[scale] = v


## A copy that set_value() may change without touching this one.
func copy() -> IntentWeights:
	var w := IntentWeights.new()
	for name: String in _weights:
		var leans: Array[float] = []
		leans.assign(_weights[name].leans)
		w._weights[name] = {"base": float(_weights[name].base), "leans": leans}
	w._roles = _roles.duplicate()
	w.lean_floor = lean_floor
	return w
