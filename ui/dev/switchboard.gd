class_name Switchboard
extends RefCounted
## Every open design decision in one place, for the switchboard screen: the
## decisions and options of data/variants/variants.json, plus the ones other
## data files own (draft_rule in data/bot_data/tuning.json, one map variant
## per act in data/tuning/acts.json). The player's choices are kept in
## user://variants.json, which the layers' own readers (FightVariants, ...)
## read when a fight or run starts. Only non-default choices are stored.
##
## A decision here is a Dictionary:
##   {id, name, layer, applies, default, options: [{id, name, description, built}]}
## A per-act decision ("act-maps") becomes one decision per act, "act-maps/act1"...

const DATA_PATH := "res://data/variants/variants.json"
const USER_PATH := FightVariants.USER_PATH
const ACT_MAPS := "act-maps"
const DRAFT_RULE := "draft-rule"
const APPLIES_TEXT := {"live": "live", "next_fight": "next fight", "next_run": "next run"}

var decisions: Array[Dictionary] = []
## Decision id -> the chosen option, for non-default choices only.
var choices: Dictionary[String, String] = {}
var user_path := USER_PATH
var errors: Array[String] = []


static func load_board(p_user_path := USER_PATH, data_path := DATA_PATH) -> Switchboard:
	var board := Switchboard.new()
	board.user_path = p_user_path
	var data := _read_json(data_path)
	for entry: Variant in data.get("decisions", []):
		if entry is Dictionary:
			board._add(entry)
	var user := _read_json(p_user_path) if FileAccess.file_exists(p_user_path) else {}
	var picked: Variant = user.get("choices", {})
	if picked is Dictionary:
		for id: Variant in picked:
			board.choose(str(id), str(picked[id]))
	return board


func decision(id: String) -> Dictionary:
	for d in decisions:
		if d.id == id:
			return d
	return {}


## The option `id` plays: the player's choice, else the default.
func option_of(id: String) -> String:
	return choices.get(id, decision(id).get("default", ""))


func has_option(id: String, option: String) -> bool:
	for o: Dictionary in decision(id).get("options", []):
		if o.id == option:
			return true
	return false


## False when some code implements `option`, true when it is only listed.
func is_built(id: String, option: String) -> bool:
	for o: Dictionary in decision(id).get("options", []):
		if o.id == option:
			return o.built
	return false


## Chooses `option` for decision `id`; choosing the default forgets the
## choice. False, and nothing changes, if either is unknown. Call save().
func choose(id: String, option: String) -> bool:
	if not has_option(id, option):
		return false
	if option == decision(id).default:
		choices.erase(id)
	else:
		choices[id] = option
	return true


func reset() -> void:
	choices.clear()


func save() -> Error:
	return JsonFile.write(user_path, {"choices": choices}, "\t")


## "d-wait=extra_energy · draft-rule=damage_guarantee", in decision order;
## "" when every choice is the default.
func summary() -> String:
	var parts := PackedStringArray()
	for d in decisions:
		if choices.has(d.id):
			parts.append("%s=%s" % [d.id, choices[d.id]])
	return " · ".join(parts)


func draft_rule() -> String:
	return option_of(DRAFT_RULE)


## One map variant id per act, for RunFlow.map_variants.
func act_map_variants() -> PackedStringArray:
	var out := PackedStringArray()
	for d in decisions:
		if str(d.id).begins_with(ACT_MAPS + "/"):
			out.append(option_of(d.id))
	return out


func _add(entry: Dictionary) -> void:
	var base := {
		"id": str(entry.get("id", "")),
		"name": str(entry.get("name", "")),
		"layer": str(entry.get("layer", "")),
		"applies": str(entry.get("applies", "next_run")),
		"default": str(entry.get("default", "")),
		"options": [],
	}
	if entry.get("per_act", false):
		_add_acts(base, str(entry.get("options_from", "")))
		return
	for o: Variant in entry.get("options", []):
		if o is Dictionary:
			base.options.append({
				"id": str(o.get("id", "")),
				"name": str(o.get("name", "")),
				"description": str(o.get("description", "")),
				"built": bool(o.get("built", true)),
			})
	if entry.has("default_from"):
		var source := _read_json(str(entry.default_from))
		base.default = str(source.get(str(entry.get("default_key", "")), ""))
	if not has_option_in(base, base.default):
		errors.append("%s: default '%s' is not one of its options" % [base.id, base.default])
	decisions.append(base)


func _add_acts(base: Dictionary, acts_file: String) -> void:
	var plan := ActPlan.load_file(acts_file)
	if not plan.is_valid():
		errors.append("%s: cannot read %s" % [base.id, acts_file])
		return
	for act in plan.act_count():
		var d := base.duplicate(true)
		d.id = "%s/act%d" % [base.id, act + 1]
		d.name = "%s: act %d, %s" % [base.name, act + 1, plan.act_name(act)]
		d.default = plan.chosen_variant(act)
		for variant: Dictionary in plan.variants(act):
			d.options.append({"id": variant.id, "name": variant.name, "description": variant.region_file, "built": true})
		decisions.append(d)


static func has_option_in(d: Dictionary, option: String) -> bool:
	return d.options.any(func(o: Dictionary) -> bool: return o.id == option)


static func _read_json(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	return JsonFile.read_dict(path)
