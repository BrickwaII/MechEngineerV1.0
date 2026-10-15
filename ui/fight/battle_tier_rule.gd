class_name BattleTierRule
extends RefCounted
## Which strength tier (beginner, medium, advanced) a bot is drawn in: the
## tier-rule switch of the variant switchboard (data/variants/variants.json).
## Needs no scene.
##
##   generation    the bot's personality generation (default)
##   skill_levels  the levels gained across its skills: each level above 1, summed
##   augments      the augments fitted in its slots
##
## Each option's params hold its thresholds: a score of medium_at or more is
## medium, advanced_at or more is advanced, anything lower is beginner.
## TODO(decision: tier-rule): default "generation" until playtests pick one.
##
##   var rule := BattleTierRule.load_active()
##   var tier := rule.tier_for(BattleTierRule.info_for_bot(bot))

const DECISION := "tier-rule"
const GENERATION := "generation"
const SKILL_LEVELS := "skill_levels"
const AUGMENTS := "augments"
const RULES: Array[String] = [GENERATION, SKILL_LEVELS, AUGMENTS]

var rule := GENERATION
var medium_at := 2
var advanced_at := 3
var errors: Array[String] = []


## The rule the switchboard plays: the player's choice in `user_path`, else
## the default, with that option's thresholds.
static func load_active(user_path := FightVariants.USER_PATH, data_path := FightVariants.DEFAULT_PATH) -> BattleTierRule:
	var data := _read_json(data_path)
	var decision := {}
	for d: Variant in data.get("decisions", []):
		if d is Dictionary and d.get("id", "") == DECISION:
			decision = d
	if decision.is_empty():
		var missing := BattleTierRule.new()
		missing.errors.append("no %s decision in %s" % [DECISION, data_path])
		return missing
	var chosen := str(decision.get("default", GENERATION))
	var user := _read_json(user_path) if not user_path.is_empty() and FileAccess.file_exists(user_path) else {}
	var picked: Variant = user.get("choices", {})
	if picked is Dictionary and picked.has(DECISION):
		chosen = str(picked[DECISION])
	for o: Variant in decision.get("options", []):
		if o is Dictionary and o.get("id", "") == chosen:
			return from_option(chosen, o.get("params", {}))
	var fallback := from_option(str(decision.get("default", GENERATION)), {})
	fallback.errors.append("unknown %s option '%s'" % [DECISION, chosen])
	return fallback


## The defaults of data/variants/variants.json, ignoring the player's choices.
static func defaults() -> BattleTierRule:
	return load_active("")


static func from_option(p_rule: String, params: Dictionary) -> BattleTierRule:
	var r := BattleTierRule.new()
	r.rule = p_rule if p_rule in RULES else GENERATION
	if not p_rule in RULES:
		r.errors.append("unknown tier rule '%s'" % p_rule)
	r.medium_at = int(params.get("medium_at", r.medium_at))
	r.advanced_at = int(params.get("advanced_at", r.advanced_at))
	if r.advanced_at < r.medium_at:
		r.errors.append("advanced_at %d is below medium_at %d" % [r.advanced_at, r.medium_at])
	return r


## What the rule measures for a bot described by `info`
## ({generation: int, skill_levels: Array of int, augments: int}).
func score(info: Dictionary) -> int:
	match rule:
		SKILL_LEVELS:
			var gained := 0
			for level: Variant in info.get("skill_levels", []):
				gained += maxi(0, int(level) - 1)
			return gained
		AUGMENTS:
			return int(info.get("augments", 0))
	return int(info.get("generation", 1))


## "beginner", "medium" or "advanced" (the manifest's tier names, weakest first).
func tier_for(info: Dictionary) -> String:
	return tier_name(tier_index(info))


## 0, 1 or 2.
func tier_index(info: Dictionary) -> int:
	var s := score(info)
	if s >= advanced_at:
		return 2
	if s >= medium_at:
		return 1
	return 0


static func tier_name(index: int) -> String:
	var tiers := SpriteManifest.tiers()
	if tiers.is_empty():
		return ["beginner", "medium", "advanced"][clampi(index, 0, 2)]
	return tiers[clampi(index, 0, tiers.size() - 1)]


## What the rule needs to know about a bot.
static func info_for_bot(bot: Bot) -> Dictionary:
	var levels: Array[int] = []
	for skill in bot.skills:
		if skill != null:
			levels.append(skill.level)
	var fitted := 0
	for slot in bot.augment_slots:
		if slot != null and not slot.is_empty():
			fitted += 1
	var generation := bot.personality.generation if bot.personality != null else Personality.MIN_GENERATION
	return {"generation": generation, "skill_levels": levels, "augments": fitted}


## The same for a fighting unit with no Bot behind it (stub squads, tools):
## its skill levels are known, its generation and augments are not, so they
## count as the lowest.
static func info_for_combatant(unit: Combatant) -> Dictionary:
	var levels: Array[int] = []
	for skill in unit.skills():
		levels.append(skill.level)
	return {"generation": Personality.MIN_GENERATION, "skill_levels": levels, "augments": 0}


static func _read_json(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	return JsonFile.read_dict(path)
