class_name FightVariants
extends RefCounted
## The fight layer's switches from the variant switchboard
## (data/variants/variants.json): one chosen option per fight decision, and
## that option's params. Only decisions with "layer": "fight" are read.
##
##   var v := FightVariants.load_active()     # defaults + the player's choices
##   if v.option(FightVariants.WAIT_FORM) == FightVariants.WAIT_EXTRA_ENERGY: ...
##
## defaults() ignores the player's choices; tests and CombatTuning use it, so
## a choice saved in user:// never changes a test. The game loads the active
## set when each fight starts (see ui/run/).

const DEFAULT_PATH := "res://data/variants/variants.json"
## The player's choices, written by the switchboard screen (ui/dev/).
const USER_PATH := "user://variants.json"
const LAYER := "fight"

const WAIT_FORM := "d-wait"
const WAIT_BANKED := "banked"
const WAIT_EXTRA_ENERGY := "extra_energy"
const WAIT_BONUS_DAMAGE := "bonus_damage"

const WAIT_LENGTH := "d-wait-length"
const WAIT_LENGTH_SNAP := "snap"
const WAIT_LENGTH_EXACT := "exact"

const ELASTICITY := "d-elasticity"
const ELASTICITY_NONE := "none"
const ELASTICITY_BIG_HITS := "reduce_big_hits"
const ELASTICITY_KNOCKBACK := "resist_knockback"
const ELASTICITY_ENERGY := "energy_when_hit"

const PERSONALITY_MAP := "d-personality-map"
const PERSONALITY_CURRENT := "current"
const PERSONALITY_BY_TARGET := "by_target"
const PERSONALITY_OFF := "off"

## How bot skills grow. TODO(decision: skill-ranks).
const SKILL_PROGRESSION := "skill-progression"
const PROGRESSION_RANKS := "ranks"
const PROGRESSION_FLAT := "flat_levels"

## What one tagged decision counts for in personality drift.
const TAG_WEIGHT := "tag-weight"
const TAG_WEIGHT_PER_ACTION := "per_action"
const TAG_WEIGHT_PER_ENERGY := "per_energy"

const HP_CARRYOVER := "hp-carryover"
const HP_FULL_HEAL := "full_heal"
const HP_CARRY := "carry"
const HP_PARTIAL_HEAL := "partial_heal"

const ENEMY_FACTIONS := "enemy-factions"
const FACTIONS_BY_ACT := "by_act"
const FACTIONS_MIXED := "mixed"
const FACTIONS_GENERIC := "generic"

## Every fight decision this class knows, with the options code implements.
const KNOWN := {
	WAIT_FORM: [WAIT_BANKED, WAIT_EXTRA_ENERGY, WAIT_BONUS_DAMAGE],
	WAIT_LENGTH: [WAIT_LENGTH_SNAP, WAIT_LENGTH_EXACT],
	ELASTICITY: [ELASTICITY_NONE, ELASTICITY_BIG_HITS, ELASTICITY_KNOCKBACK, ELASTICITY_ENERGY],
	PERSONALITY_MAP: [PERSONALITY_CURRENT, PERSONALITY_BY_TARGET, PERSONALITY_OFF],
	SKILL_PROGRESSION: [PROGRESSION_RANKS, PROGRESSION_FLAT],
	TAG_WEIGHT: [TAG_WEIGHT_PER_ACTION, TAG_WEIGHT_PER_ENERGY],
	HP_CARRYOVER: [HP_FULL_HEAL, HP_CARRY, HP_PARTIAL_HEAL],
	ENEMY_FACTIONS: [FACTIONS_BY_ACT, FACTIONS_MIXED, FACTIONS_GENERIC],
}

## Decision id -> its default option id.
var defaults_by_decision: Dictionary[String, String] = {}
## Decision id -> the chosen option id.
var choices: Dictionary[String, String] = {}
## Decision id -> {option id -> params Dictionary}.
var params_by_option := {}
var errors: Array[String] = []

static var _cached_defaults: Dictionary = {}


## The data file's defaults, with no player choices. The file is read once.
static func defaults() -> FightVariants:
	if _cached_defaults.is_empty():
		_cached_defaults = _read_json(DEFAULT_PATH)
	return from_dict(_cached_defaults)


## The defaults with the player's choices from `user_path` on top. A missing
## or broken user file is ignored, as is a choice of an unknown option.
static func load_active(user_path := USER_PATH) -> FightVariants:
	var v := defaults()
	var user := _read_json(user_path) if FileAccess.file_exists(user_path) else {}
	var picked: Variant = user.get("choices", {})
	if picked is Dictionary:
		for decision: Variant in picked:
			if v.choices.has(str(decision)):
				v.choose(str(decision), str(picked[decision]))
	return v


static func from_dict(data: Dictionary) -> FightVariants:
	var v := FightVariants.new()
	var list: Variant = data.get("decisions", [])
	if not list is Array:
		v.errors.append("decisions must be a list")
		list = []
	for entry: Variant in list:
		if not entry is Dictionary or str(entry.get("layer", "")) != LAYER:
			continue
		var id := str(entry.get("id", ""))
		var options := {}
		for o: Variant in entry.get("options", []):
			if o is Dictionary:
				options[str(o.get("id", ""))] = (o.get("params", {}) as Dictionary).duplicate(true)
		var def := str(entry.get("default", ""))
		if not options.has(def):
			v.errors.append("%s: default '%s' is not one of its options" % [id, def])
		v.params_by_option[id] = options
		v.defaults_by_decision[id] = def
		v.choices[id] = def
	for id: String in KNOWN:
		if not v.choices.has(id):
			v.errors.append("decision %s is missing from the switchboard" % id)
			v.choices[id] = KNOWN[id][0]
			v.defaults_by_decision[id] = KNOWN[id][0]
			v.params_by_option[id] = {}
		for option: String in KNOWN[id]:
			if not (v.params_by_option[id] as Dictionary).has(option):
				v.errors.append("%s: option %s is missing from the switchboard" % [id, option])
	return v


## Chooses `option` for `decision`. False, and nothing changes, if either is
## unknown.
func choose(decision: String, option: String) -> bool:
	if not params_by_option.has(decision) or not (params_by_option[decision] as Dictionary).has(option):
		return false
	choices[decision] = option
	return true


## The chosen option of `decision`, or "" if the decision is unknown.
func option(decision: String) -> String:
	return choices.get(decision, "")


func is_chosen(decision: String, p_option: String) -> bool:
	return option(decision) == p_option


## A number from the chosen option's params, or `fallback` if it has none.
func param_int(decision: String, key: String, fallback := 0) -> int:
	return int(_params(decision).get(key, fallback))


func param_float(decision: String, key: String, fallback := 0.0) -> float:
	return float(_params(decision).get(key, fallback))


func param_string(decision: String, key: String, fallback := "") -> String:
	return str(_params(decision).get(key, fallback))


## Decision id -> option id for every choice that is not the default.
func non_default() -> Dictionary[String, String]:
	var out: Dictionary[String, String] = {}
	for id in choices:
		if choices[id] != defaults_by_decision.get(id, ""):
			out[id] = choices[id]
	return out


func duplicate_variants() -> FightVariants:
	var v := FightVariants.new()
	v.defaults_by_decision = defaults_by_decision.duplicate()
	v.choices = choices.duplicate()
	v.params_by_option = params_by_option.duplicate(true)
	v.errors = errors.duplicate()
	return v


func _params(decision: String) -> Dictionary:
	return (params_by_option.get(decision, {}) as Dictionary).get(option(decision), {})


static func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
