class_name PersonalityDrift
extends RefCounted
## Personality drift: tallied from a finished fight's decisions, applied once.
##
## Nothing here runs while a fight is in progress, so no Personality value
## changes mid-fight. After the last action, PostFight tallies every decision a
## bot made against the drift rules in data/post_fight/post_fight.json, then
## applies the net result to each scale exactly once.
##
## Default mapping, TODO(decision: d-personality-map) until signed off:
##   hit_enemy                      -> aggressive
##   self_target with brace/shield  -> defensive
##   ally_target                    -> supportive
##   solo (no ally acted between)   -> solitary
##   wait                           -> methodical
##   first_affordable               -> reactive
## Each push moves its scale by drift.per_push toward the pole; opposite pushes
## cancel; the net move per scale is capped at drift.max_per_scale_per_fight.
## Only scales active for the bot's generation move.


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


## Pushes per pole from `actor_id`'s decisions in `tags`. Every pole is a key.
static func tally(tags: Array[ActionTag], actor_id: String, tuning: PostFightTuning) -> Dictionary[String, int]:
	var pushes: Dictionary[String, int] = {}
	for scale: int in Personality.POLES:
		for pole: String in Personality.POLES[scale]:
			pushes[pole] = 0
	for tag in tags:
		if tag.actor_id != actor_id:
			continue
		for rule in tuning.drift_rules:
			if rule.matches(tag) and pushes.has(rule.pole):
				pushes[rule.pole] += 1
	return pushes


## The change to each scale, in Scale order, for `personality`. Inactive
## scales get 0.
static func shifts(pushes: Dictionary[String, int], personality: Personality, tuning: PostFightTuning) -> Array[float]:
	var out: Array[float] = []
	for scale in Personality.SCALE_COUNT:
		if not personality.is_active(scale):
			out.append(0.0)
			continue
		var poles: Array = Personality.POLES[scale]
		var net: int = pushes.get(poles[1], 0) - pushes.get(poles[0], 0)
		var cap := tuning.max_drift_per_scale_per_fight
		out.append(clampf(net * tuning.drift_per_push, -cap, cap))
	return out


## Adds `scale_shifts` to `personality`. Personality clamps to -1..1.
static func apply(personality: Personality, scale_shifts: Array[float]) -> void:
	personality.aggressive_defensive += scale_shifts[Personality.Scale.AGGRESSIVE_DEFENSIVE]
	personality.solitary_supportive += scale_shifts[Personality.Scale.SOLITARY_SUPPORTIVE]
	personality.reactive_methodical += scale_shifts[Personality.Scale.REACTIVE_METHODICAL]


## The raw value of every scale, in Scale order.
static func values_of(personality: Personality) -> Array[float]:
	var out: Array[float] = []
	for scale in Personality.SCALE_COUNT:
		out.append(personality.get_raw_value(scale))
	return out
