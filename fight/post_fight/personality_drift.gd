class_name PersonalityDrift
extends RefCounted
## Personality drift: tallied from a finished fight's decisions, applied once.
##
## Nothing here runs while a fight is in progress, so no Personality value
## changes mid-fight. After the last action, PostFight tallies every decision a
## bot made against the drift rules in data/post_fight/post_fight.json, then
## grows each personality end exactly once.
##
## Both ends of a spectrum only ever grow: a push adds to its own end and never
## takes from the other, so a bot that zigzags grows both and the larger end
## wins out. Every spectrum grows from generation 1 on, and no end has a cap.
##
## Default mapping, TODO(decision: d-personality-map) until signed off:
##   hit_enemy                      -> aggressive
##   self_target with brace/shield  -> defensive
##   ally_target                    -> supportive
##   solo (no ally acted between)   -> solitary
##   wait                           -> methodical
##   first_affordable               -> reactive
## Each push grows its end by drift.per_push; one end grows at most
## drift.max_per_end_per_fight in one fight. With the tag-weight switch on
## per_energy, a decision counts energy spent / energy_per_push pushes (at
## least min_weight) instead of one. The d-personality-map switch
## (data/variants/variants.json) can swap the mapping for
## drift_rule_sets.by_target or turn drift off; see PostFightTuning.for_variants().


## The scale a pole belongs to, or -1 if `pole` names no pole.
static func scale_of_pole(pole: String) -> int:
	for scale: int in Personality.POLES:
		if pole in Personality.POLES[scale]:
			return scale
	return -1


## -1 for the first-named pole of its scale, +1 for the second.
static func direction_of_pole(pole: String) -> int:
	var scale := scale_of_pole(pole)
	if scale < 0:
		return 0
	return -1 if Personality.POLES[scale][0] == pole else 1


## What one decision counts for: 1, or by energy spent with per_energy.
static func weight_of(tag: ActionTag, tuning: PostFightTuning) -> float:
	if tuning.tag_weight != FightVariants.TAG_WEIGHT_PER_ENERGY:
		return 1.0
	var spent := float(tag.energy_cost_milli) / Combatant.MILLI if tag.kind == FightAction.Kind.SKILL else 0.0
	return maxf(tuning.min_weight, spent / maxf(tuning.energy_per_push, 0.001))


## Weighted pushes per end from `actor_id`'s decisions in `tags`. Every end
## is a key.
static func tally(tags: Array[ActionTag], actor_id: String, tuning: PostFightTuning) -> Dictionary[String, float]:
	var pushes: Dictionary[String, float] = {}
	for pole in Personality.ENDS:
		pushes[pole] = 0.0
	for tag in tags:
		if tag.actor_id != actor_id:
			continue
		var weight := weight_of(tag, tuning)
		for rule in tuning.drift_rules:
			if rule.matches(tag) and pushes.has(rule.pole):
				pushes[rule.pole] += weight
	return pushes


## How much each end grows, in Personality.ENDS order. Never negative.
static func growth(pushes: Dictionary[String, float], tuning: PostFightTuning) -> Array[float]:
	var out: Array[float] = []
	for pole in Personality.ENDS:
		var grow := maxf(0.0, pushes.get(pole, 0.0) * tuning.drift_per_push)
		out.append(minf(grow, maxf(0.0, tuning.max_drift_per_end_per_fight)))
	return out


## Adds `end_growth` (Personality.ENDS order) to `personality`'s ends.
static func apply(personality: Personality, end_growth: Array[float]) -> void:
	for i in Personality.ENDS.size():
		var pole := Personality.ENDS[i]
		personality.set(pole, personality.get_end(pole) + maxf(0.0, end_growth[i]))


## Every end's value, in Personality.ENDS order.
static func values_of(personality: Personality) -> Array[float]:
	return personality.get_ends()
