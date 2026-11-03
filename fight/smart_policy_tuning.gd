class_name SmartPolicyTuning
extends RefCounted
## SmartFightPolicy's numbers, from data/combat/smart_policy.json.

const DEFAULT_PATH := "res://data/combat/smart_policy.json"

## Brace against a telegraphed hit that would take at least this percent of
## the bot's current HP.
var brace_hp_percent := 30
## Upcoming turns read to see whether the hit lands before the bot acts again.
var order_lookahead := 8


static func load_default() -> SmartPolicyTuning:
	return load_file(DEFAULT_PATH)


## The tuning in `path`; the defaults (with an error pushed) when it cannot be
## read or is invalid.
static func load_file(path: String) -> SmartPolicyTuning:
	var parsed: Variant = JsonFile.read_object_cached(path)
	if parsed == null:
		push_error("SmartPolicyTuning: cannot read %s" % path)
		return SmartPolicyTuning.new()
	var t := from_dict(parsed)
	var problems := t.validate()
	if not problems.is_empty():
		push_error("SmartPolicyTuning: %s: %s" % [path, "; ".join(problems)])
		return SmartPolicyTuning.new()
	return t


static func from_dict(d: Dictionary) -> SmartPolicyTuning:
	var t := SmartPolicyTuning.new()
	t.brace_hp_percent = int(d.get("brace_hp_percent", t.brace_hp_percent))
	t.order_lookahead = int(d.get("order_lookahead", t.order_lookahead))
	return t


func validate() -> Array[String]:
	var problems: Array[String] = []
	if brace_hp_percent < 0:
		problems.append("brace_hp_percent must not be negative")
	if order_lookahead < 2:
		problems.append("order_lookahead must be at least 2")
	return problems
