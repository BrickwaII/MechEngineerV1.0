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
## Growth of a personality end per push, before the cap.
var drift_per_push: float
## The most one end may grow in one fight.
var max_drift_per_end_per_fight: float
## What one tagged decision counts for: FightVariants.TAG_WEIGHT_PER_ACTION
## (one push) or TAG_WEIGHT_PER_ENERGY (energy spent / energy_per_push pushes,
## at least min_weight), TAG_WEIGHT_PER_TURN_TIME (the ticks since the bot's
## previous decision / ticks_per_push pushes) or TAG_WEIGHT_PER_FIGHT (each
## bot's decisions share pushes_per_fight pushes). Set from the tag-weight
## switch by for_variants().
var tag_weight := FightVariants.TAG_WEIGHT_PER_ACTION
var energy_per_push := 1.0
var min_weight := 0.0
var ticks_per_push := 1.0
var pushes_per_fight := 1.0
## FightVariants.PROGRESSION_RANKS or PROGRESSION_FLAT, from the
## skill-progression switch. Ranks read `ranks`; flat levels the three below.
var progression := FightVariants.PROGRESSION_RANKS
var ranks: SkillRanks
## Flat levels: uses that make one level step.
var uses_per_level: int
## Levels gained per step.
var levels_per_step: int
var max_level: int
## Defense of the target the level-up callout's damage numbers are against.
var reference_defense := 0
## Combat skill id -> bot Skill.effect_id. "" when no bot skill matches.
var combat_skill_effects: Dictionary[String, String] = {}


## The shipped file; read from disk once, a fresh object every call.
static func load_default() -> PostFightTuning:
	var d: Variant = JsonFile.read_object_cached(DEFAULT_PATH)
	return from_dict(d) if d != null else load_file(DEFAULT_PATH)


static func load_file(path: String) -> PostFightTuning:
	var d: Variant = JsonFile.read_object(path)
	if d == null:
		push_error("PostFightTuning: cannot read %s" % path)
		return null
	return from_dict(d)


static func from_dict(d: Dictionary) -> PostFightTuning:
	var t := PostFightTuning.new()
	t.drift_rules = _read_rules(d.drift_rules)
	var sets: Dictionary = d.get("drift_rule_sets", {})
	for set_name: String in sets:
		t.drift_rule_sets[set_name] = _read_rules(sets[set_name])
	t.drift_per_push = float(d.drift.per_push)
	t.max_drift_per_end_per_fight = float(d.drift.max_per_end_per_fight)
	t.ranks = SkillRanks.load_default()
	t.apply_variants(FightVariants.defaults())
	t.uses_per_level = int(d.skill_levels.uses_per_level)
	t.levels_per_step = int(d.skill_levels.levels_per_step)
	t.max_level = int(d.skill_levels.max_level)
	t.reference_defense = int(d.get("level_up_callout", {}).get("reference_defense", 0))
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


## This file's tuning with the drift rules, tag weight and skill progression
## `variants` picks.
static func for_variants(variants: FightVariants, path := DEFAULT_PATH) -> PostFightTuning:
	var t := load_file(path)
	var set_name := variants.param_string(FightVariants.PERSONALITY_MAP, "rule_set", RULE_SET_CURRENT)
	if not t.use_rule_set(set_name):
		push_error("PostFightTuning: no drift rule set '%s'" % set_name)
	t.apply_variants(variants)
	return t


## Takes the tag weight and skill progression from `variants`.
func apply_variants(variants: FightVariants) -> void:
	tag_weight = variants.option(FightVariants.TAG_WEIGHT)
	energy_per_push = variants.param_float(FightVariants.TAG_WEIGHT, "energy_per_push", 1.0)
	min_weight = variants.param_float(FightVariants.TAG_WEIGHT, "min_weight", 0.0)
	ticks_per_push = variants.param_float(FightVariants.TAG_WEIGHT, "ticks_per_push", 1.0)
	pushes_per_fight = variants.param_float(FightVariants.TAG_WEIGHT, "pushes_per_fight", 1.0)
	progression = variants.option(FightVariants.SKILL_PROGRESSION)


func uses_ranks() -> bool:
	return progression == FightVariants.PROGRESSION_RANKS and ranks != null


## The highest skill level the progression allows.
func top_level() -> int:
	return ranks.max_rank() if uses_ranks() else max_level


## Uses that take a skill from `level` to the next; 0 at the top.
func uses_to_next(level: int) -> int:
	if uses_ranks():
		return ranks.uses_to_rank_up(level)
	return uses_per_level if level < max_level else 0


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
	if max_drift_per_end_per_fight < 0.0:
		problems.append("drift max_per_end_per_fight may not be negative")
	if tag_weight == FightVariants.TAG_WEIGHT_PER_ENERGY and energy_per_push <= 0.0:
		problems.append("tag-weight energy_per_push must be above 0")
	if tag_weight == FightVariants.TAG_WEIGHT_PER_TURN_TIME and ticks_per_push <= 0.0:
		problems.append("tag-weight ticks_per_push must be above 0")
	if tag_weight == FightVariants.TAG_WEIGHT_PER_FIGHT and pushes_per_fight < 0.0:
		problems.append("tag-weight pushes_per_fight may not be negative")
	if ranks != null:
		problems.append_array(ranks.validate())
	if uses_per_level < 1:
		problems.append("uses_per_level must be at least 1")
	if levels_per_step < 0:
		problems.append("levels_per_step may not be negative")
	if max_level < Skill.MIN_LEVEL:
		problems.append("max_level must be at least %d" % Skill.MIN_LEVEL)
	return problems
