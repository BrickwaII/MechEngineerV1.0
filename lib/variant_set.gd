class_name VariantSet
extends RefCounted
## The switchboard's choices for one layer: every decision with its options,
## each option's params, the default and the chosen option. FightVariants and
## CampaignVariants extend it with their decisions (KNOWN) and the rules
## that read them; the data is data/variants/variants.json, one "layer" each.

## Decision id -> its default option id.
var defaults_by_decision: Dictionary[String, String] = {}
## Decision id -> the chosen option id.
var choices: Dictionary[String, String] = {}
## Decision id -> {option id -> params Dictionary}.
var params_by_option := {}
var errors: Array[String] = []


## Reads the decisions of `layer` from switchboard `data` into this set, and
## checks them against `known` (decision id -> option ids the code
## implements). A known decision missing from the data gets its first known
## option. With `known_only`, decisions the code does not know are skipped.
func read_decisions(data: Dictionary, layer: String, known: Dictionary, known_only := false) -> void:
	var list: Variant = data.get("decisions", [])
	if not list is Array:
		errors.append("decisions must be a list")
		list = []
	for entry: Variant in list:
		if not entry is Dictionary or str(entry.get("layer", "")) != layer:
			continue
		var id := str(entry.get("id", ""))
		if known_only and not known.has(id):
			continue
		var options := {}
		for o: Variant in entry.get("options", []):
			if o is Dictionary:
				options[str(o.get("id", ""))] = (o.get("params", {}) as Dictionary).duplicate(true)
		var def := str(entry.get("default", ""))
		if not options.has(def):
			errors.append("%s: default '%s' is not one of its options" % [id, def])
		params_by_option[id] = options
		defaults_by_decision[id] = def
		choices[id] = def
	for id: String in known:
		if not choices.has(id):
			errors.append("decision %s is missing from the switchboard" % id)
			choices[id] = known[id][0]
			defaults_by_decision[id] = known[id][0]
			params_by_option[id] = {}
		for option: String in known[id]:
			if not (params_by_option[id] as Dictionary).has(option):
				errors.append("%s: option %s is missing from the switchboard" % [id, option])


## Chooses `option` for `decision`. False, and nothing changes, if either is
## unknown.
func choose(decision: String, option: String) -> bool:
	if not params_by_option.has(decision) or not (params_by_option[decision] as Dictionary).has(option):
		return false
	choices[decision] = option
	return true


## Chooses each decision -> option in `picked` (a user file's "choices");
## unknown decisions and options are ignored.
func choose_all(picked: Variant) -> void:
	if picked is Dictionary:
		for decision: Variant in picked:
			choose(str(decision), str(picked[decision]))


## The chosen option of `decision`, or "" if the decision is unknown.
func option(decision: String) -> String:
	return choices.get(decision, "")


func is_chosen(decision: String, p_option: String) -> bool:
	return option(decision) == p_option


## The chosen option's params for `decision`.
func params(decision: String) -> Dictionary:
	return (params_by_option.get(decision, {}) as Dictionary).get(option(decision), {})


## A number or text from the chosen option's params, or `fallback` if it has none.
func param_int(decision: String, key: String, fallback := 0) -> int:
	return int(params(decision).get(key, fallback))


func param_float(decision: String, key: String, fallback := 0.0) -> float:
	return float(params(decision).get(key, fallback))


func param_string(decision: String, key: String, fallback := "") -> String:
	return str(params(decision).get(key, fallback))


## Decision id -> option id for every choice that is not the default.
func non_default() -> Dictionary[String, String]:
	var out: Dictionary[String, String] = {}
	for id in choices:
		if choices[id] != defaults_by_decision.get(id, ""):
			out[id] = choices[id]
	return out


## Copies this set's decisions, choices and errors into `into`, a new set of
## the same kind, and returns it.
func copy_into(into: VariantSet) -> VariantSet:
	into.defaults_by_decision = defaults_by_decision.duplicate()
	into.choices = choices.duplicate()
	into.params_by_option = params_by_option.duplicate(true)
	into.errors = errors.duplicate()
	return into
