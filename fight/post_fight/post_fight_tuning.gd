class_name PostFightTuning
extends RefCounted
## Every post-fight number, loaded from data/post_fight/post_fight.json.
## Tests may build one with from_dict() and change fields directly.

const DEFAULT_PATH := "res://data/post_fight/post_fight.json"
const RULE_SET_CURRENT := "current"
const RULE_SET_OFF := "off"

## One drift rule: a decision carrying `label` (and, when `skills` is not
## empty, using one of those skills) pushes `pole`.
class DriftRule:
	var label: String
	var skills: Array[String] = []
	var pole: String

	func matches(tag: ActionTag) -> bool:
		return tag.has_label(label) and (skills.is_empty() or tag.skill_id in skills)


var drift_rules: Array[DriftRule] = []
## Rule set name -> other drift rules the d-personality-map switch can pick.
var drift_rule_sets: Dictionary[String, Array] = {}
## Personality change per push, before the cap.
var drift_per_push: float
## The most one scale may move in one fight, either way.
var max_drift_per_scale_per_fight: float
## Uses that make one level step.
var uses_per_level: int
## Levels gained per step.
var levels_per_step: int
var max_level: int
## Combat skill id -> bot Skill.effect_id. "" when no bot skill matches.
var combat_skill_effects: Dictionary[String, String] = {}


static func load_default() -> PostFightTuning:
	return load_file(DEFAULT_PATH)


static func load_file(path: String) -> PostFightTuning:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("PostFightTuning: cannot read %s" % path)
		return null
	return from_dict(parsed)


static func from_dict(d: Dictionary) -> PostFightTuning:
	var t := PostFightTuning.new()
	t.drift_rules = _read_rules(d.drift_rules)
	var sets: Dictionary = d.get("drift_rule_sets", {})
	for set_name: String in sets:
		t.drift_rule_sets[set_name] = _read_rules(sets[set_name])
	t.drift_per_push = float(d.drift.per_push)
	t.max_drift_per_scale_per_fight = float(d.drift.max_per_scale_per_fight)
	t.uses_per_level = int(d.skill_levels.uses_per_level)
	t.levels_per_step = int(d.skill_levels.levels_per_step)
	t.max_level = int(d.skill_levels.max_level)
	for id: String in d.combat_skill_effects:
		t.combat_skill_effects[id] = String(d.combat_skill_effects[id])
	return t


## The drift rules for the d-personality-map rule set `set_name`: "current"
## keeps drift_rules, "off" has none, any other name is one of
## drift_rule_sets. False, and nothing changes, for an unknown name.
func use_rule_set(set_name: String) -> bool:
	match set_name:
		RULE_SET_CURRENT:
			return true
		RULE_SET_OFF:
			drift_rules = []
			return true
	if not drift_rule_sets.has(set_name):
		return false
	drift_rules.assign(drift_rule_sets[set_name])
	return true


## This file's tuning with the drift rules `variants` picks.
static func for_variants(variants: FightVariants, path := DEFAULT_PATH) -> PostFightTuning:
	var t := load_file(path)
	var set_name := variants.param_string(FightVariants.PERSONALITY_MAP, "rule_set", RULE_SET_CURRENT)
	if not t.use_rule_set(set_name):
		push_error("PostFightTuning: no drift rule set '%s'" % set_name)
	return t


static func _read_rules(list: Array) -> Array[DriftRule]:
	var out: Array[DriftRule] = []
	for r: Dictionary in list:
		var rule := DriftRule.new()
		rule.label = r.label
		rule.pole = r.pole
		for s: String in r.get("skills", []):
			rule.skills.append(s)
		out.append(rule)
	return out


## Problems that would make post-fight misbehave; empty when usable.
func validate() -> Array[String]:
	var problems: Array[String] = []
	var all_rules: Array[DriftRule] = drift_rules.duplicate()
	for set_name in drift_rule_sets:
		all_rules.append_array(drift_rule_sets[set_name])
	for rule in all_rules:
		if not rule.label in ActionTag.ALL_LABELS:
			problems.append("drift rule label %s is not an ActionTag label" % rule.label)
		if PersonalityDrift.scale_of_pole(rule.pole) < 0:
			problems.append("drift rule pole %s is not a personality pole" % rule.pole)
	if drift_per_push < 0.0:
		problems.append("drift per_push may not be negative")
	if max_drift_per_scale_per_fight < 0.0:
		problems.append("drift max_per_scale_per_fight may not be negative")
	if uses_per_level < 1:
		problems.append("uses_per_level must be at least 1")
	if levels_per_step < 0:
		problems.append("levels_per_step may not be negative")
	if max_level < Skill.MIN_LEVEL:
		problems.append("max_level must be at least %d" % Skill.MIN_LEVEL)
	return problems
