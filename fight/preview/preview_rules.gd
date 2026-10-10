class_name PreviewRules
extends RefCounted
## What the preview may not predict, loaded from
## data/combat/intent/preview_rules.json: skills whose outcome is random.
## Damage is deterministic today, so by default nothing is random.

const DEFAULT_PATH := "res://data/combat/intent/preview_rules.json"

var random_skills: Array[String] = []


static func load_default() -> PreviewRules:
	return load_file(DEFAULT_PATH)


static func load_file(path: String) -> PreviewRules:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("PreviewRules: cannot read %s" % path)
		return null
	return from_dict(parsed)


static func from_dict(d: Dictionary) -> PreviewRules:
	var r := PreviewRules.new()
	for id: String in d.get("random_skills", []):
		r.random_skills.append(id)
	return r


## True when the outcome of `skill_id` cannot be known before it resolves.
func is_random(skill_id: String) -> bool:
	return skill_id in random_skills


## `amount` as a preview value: unknown when `skill_id` is random.
func value_for(skill_id: String, amount: int) -> PreviewValue:
	return PreviewValue.unknown() if is_random(skill_id) else PreviewValue.of(amount)
