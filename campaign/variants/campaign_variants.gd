class_name CampaignVariants
extends RefCounted
## The campaign layer's switches from the variant switchboard
## (data/variants/variants.json): one chosen option per campaign decision, and
## that option's params. Only decisions with "layer": "campaign" and options of
## their own are read (act-maps is applied by the run flow, not here).
##
##   var v := CampaignVariants.load_active()   # defaults + the player's choices
##   if v.is_chosen(CampaignVariants.AUTO_EXPANSION, CampaignVariants.EXPANSION_SIMPLE): ...
##
## When each takes effect:
## - next_run (energy-grid, squad-size, act-pacing, auto-expansion, escalation):
##   read once
##   when a run starts and kept in RunState.variants, so a saved run plays on
##   with the choices it began with. for_run() rebuilds them from a state.
## - next_fight (grid-cost-owner): read when each fight starts.
##
## user_path names the player's choices file. It is "" by default, which reads
## the defaults only, so a choice saved in user:// never changes a test; the
## run flow (ui/run/) points it at the switchboard's file.

const DEFAULT_PATH := "res://data/variants/variants.json"
const LAYER := "campaign"

const ENERGY_GRID := "energy-grid"
const ENERGY_SEPARATE := "separate"
const ENERGY_SHARED_POOL := "shared_pool"

const GRID_COST_OWNER := "grid-cost-owner"
const GRID_MAP_SURCHARGE := "map_surcharge"
const GRID_FIGHT_SERVICE := "fight_service"
const GRID_NO_SURCHARGE := "no_surcharge"

const SQUAD_SIZE := "squad-size"
const SQUAD_DRAFT5_FIELD3 := "draft5_field3"
const SQUAD_DRAFT4_FIELD3 := "draft4_field3"
const SQUAD_DRAFT6_FIELD4 := "draft6_field4"

const ACT_PACING := "act-pacing"
const PACING_CURRENT := "current"
const PACING_EVEN := "even"
const PACING_FASTER_LATER := "faster_later"

const ESCALATION := "escalation"
const ESCALATION_ON := "on"
const ESCALATION_OFF := "off"
const ESCALATION_QUARTERS := "quarters"

const AUTO_EXPANSION := "auto-expansion"
const EXPANSION_OFF := "off"
const EXPANSION_SIMPLE := "simple"

## Every campaign decision this class knows, with the options code implements.
const KNOWN := {
	ENERGY_GRID: [ENERGY_SEPARATE, ENERGY_SHARED_POOL],
	GRID_COST_OWNER: [GRID_MAP_SURCHARGE, GRID_FIGHT_SERVICE, GRID_NO_SURCHARGE],
	SQUAD_SIZE: [SQUAD_DRAFT5_FIELD3, SQUAD_DRAFT4_FIELD3, SQUAD_DRAFT6_FIELD4],
	ACT_PACING: [PACING_CURRENT, PACING_EVEN, PACING_FASTER_LATER],
	AUTO_EXPANSION: [EXPANSION_OFF, EXPANSION_SIMPLE],
	ESCALATION: [ESCALATION_ON, ESCALATION_OFF, ESCALATION_QUARTERS],
}
## The decisions a run keeps from its start (applies: next_run).
const RUN_DECISIONS: Array[String] = [ENERGY_GRID, SQUAD_SIZE, ACT_PACING, AUTO_EXPANSION, ESCALATION]

## The player's choices file; "" reads the defaults only. See the class notes.
static var user_path := ""

## The option a run plays for a run decision added after it began: a save or
## journal from before escalation keeps the difficulty it was played with.
const BEFORE_DECISION := {ESCALATION: ESCALATION_OFF}

## Decision id -> its default option id.
var defaults_by_decision: Dictionary[String, String] = {}
## Decision id -> the chosen option id.
var choices: Dictionary[String, String] = {}
## Decision id -> {option id -> params Dictionary}.
var params_by_option := {}
var errors: Array[String] = []

static var _cached_defaults: Dictionary = {}


## The data file's defaults, with no player choices. The file is read once.
static func defaults() -> CampaignVariants:
	if _cached_defaults.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DEFAULT_PATH))
		_cached_defaults = parsed if parsed is Dictionary else {}
	return from_dict(_cached_defaults)


## The defaults with the player's choices from `path` on top (user_path when
## left empty). A missing or broken file is ignored, as is an unknown option.
static func load_active(path := "") -> CampaignVariants:
	var v := defaults()
	var file := path if not path.is_empty() else user_path
	if file.is_empty() or not FileAccess.file_exists(file):
		return v
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
	var picked: Variant = (parsed as Dictionary).get("choices", {}) if parsed is Dictionary else {}
	if picked is Dictionary:
		for decision: Variant in picked:
			v.choose(str(decision), str(picked[decision]))
	return v


## The defaults with a run's kept choices (RunState.variants) on top. A save
## from before variants keeps none, so it plays every default, except that a
## run from before a decision in BEFORE_DECISION plays the option given there.
static func for_run(run_choices: Dictionary) -> CampaignVariants:
	var v := defaults()
	for decision: String in BEFORE_DECISION:
		if not run_choices.has(decision):
			v.choose(decision, BEFORE_DECISION[decision])
	for decision: Variant in run_choices:
		if str(decision) in RUN_DECISIONS:
			v.choose(str(decision), str(run_choices[decision]))
	return v


static func from_dict(data: Dictionary) -> CampaignVariants:
	var v := CampaignVariants.new()
	var list: Variant = data.get("decisions", [])
	if not list is Array:
		v.errors.append("decisions must be a list")
		list = []
	for entry: Variant in list:
		if not entry is Dictionary or str(entry.get("layer", "")) != LAYER or not KNOWN.has(str(entry.get("id", ""))):
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


## The chosen option's params for `decision`.
func params(decision: String) -> Dictionary:
	return (params_by_option.get(decision, {}) as Dictionary).get(option(decision), {})


func param_float(decision: String, key: String, fallback := 0.0) -> float:
	return float(params(decision).get(key, fallback))


func param_int(decision: String, key: String, fallback := 0) -> int:
	return int(params(decision).get(key, fallback))


## The choices a run keeps from its start, every run decision included, for
## RunState.variants.
func run_choices() -> Dictionary[String, String]:
	var out: Dictionary[String, String] = {}
	for id in RUN_DECISIONS:
		out[id] = option(id)
	return out


## {draft_size, squad_size} for the chosen squad-size option, or {} when it
## keeps data/bot_data/tuning.json's sizes (the default gives no params).
func squad_sizes() -> Dictionary:
	var p := params(SQUAD_SIZE)
	if not p.has("draft_size") or not p.has("squad_size"):
		return {}
	return {"draft_size": int(p["draft_size"]), "squad_size": int(p["squad_size"])}


## Decision id -> option id for every choice that is not the default.
func non_default() -> Dictionary[String, String]:
	var out: Dictionary[String, String] = {}
	for id in choices:
		if choices[id] != defaults_by_decision.get(id, ""):
			out[id] = choices[id]
	return out


func duplicate_variants() -> CampaignVariants:
	var v := CampaignVariants.new()
	v.defaults_by_decision = defaults_by_decision.duplicate()
	v.choices = choices.duplicate()
	v.params_by_option = params_by_option.duplicate(true)
	v.errors = errors.duplicate()
	return v
