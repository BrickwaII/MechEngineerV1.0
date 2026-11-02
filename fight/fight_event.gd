class_name FightEvent
extends RefCounted
## One thing that happened inside an action, for the battle presentation:
## a skill used, a hit landed, a heal, a guard raised, a wait begun, a unit
## going down. Fight raises them as it resolves an action (Fight.event_raised,
## Fight.last_events). Read-only reporting: nothing reads events back into the
## fight, so they never change a result.
##
## One action raises, in order: SKILL (or WAIT); STATUS_EXPIRED for each of
## the actor's statuses that end as it acts (BRACE_END first, for its Brace);
## then per target HIT / HEAL / GUARD / BRACE (one HIT per hit of a multi-hit
## skill), DOWN right after the HIT that downed a unit, STATUS_CONSUMED right
## after the HIT that used a status up, PLATING after a HIT on a plated unit
## and STAGGER when that breaks the plating, and STATUS_APPLIED once the
## target's hits are done. A Staggered unit's lost turn raises RECOVER on its
## own, between decisions (Fight.advance()).

enum Kind { SKILL, HIT, HEAL, GUARD, WAIT, DOWN, STATUS_APPLIED, STATUS_CONSUMED, STATUS_EXPIRED,
	PLATING, STAGGER, RECOVER, BRACE, BRACE_END }

var kind: Kind
## Fight.action_count of the action that raised it (1 for the first action).
var action_index := 0
var actor_id := ""
## The unit the event lands on. For SKILL and WAIT, the chosen target (WAIT: "").
var target_id := ""
var skill_id := ""
## The actor's level in the skill (1 for enemies and unlevelled skills).
var skill_level := 1
## HIT: damage dealt. HEAL: hp restored. GUARD: percent of the next hit blocked.
## SKILL: energy points spent. STATUS_*: the status's stacks. PLATING: pips
## stripped. STAGGER: gauge knocked back. RECOVER: plating pips restored.
## BRACE: damage it will absorb. BRACE_END: absorb left unused.
var amount := 0
## PLATING, STAGGER and RECOVER: the target's plating pips after the event.
var plating_after := 0
## HIT only: the guard percent that softened it (0 when unguarded).
var blocked_percent := 0
## HIT only: damage the target's Brace absorbed.
var absorbed := 0
## HIT only: extra damage from the target's statuses (Exposed), in percent.
var status_bonus_percent := 0
## HIT only: the skill's payoff bonus, in percent, when it applied.
var payoff_bonus_percent := 0
## STATUS_APPLIED, STATUS_CONSUMED, STATUS_EXPIRED: the status id. For
## STATUS_EXPIRED the actor and target are the holder.
var status_id := ""
var hp_before := 0
var hp_after := 0
var max_hp := 0
## SKILL and WAIT: the actor's whole energy points before and after.
var energy_before := 0
var energy_after := 0


func _init(p_kind := Kind.SKILL, p_action_index := 0, p_actor_id := "", p_target_id := "", p_skill_id := "") -> void:
	kind = p_kind
	action_index = p_action_index
	actor_id = p_actor_id
	target_id = p_target_id
	skill_id = p_skill_id


func is_damage() -> bool:
	return kind == Kind.HIT


func is_status() -> bool:
	return kind in [Kind.STATUS_APPLIED, Kind.STATUS_CONSUMED, Kind.STATUS_EXPIRED]


func _to_string() -> String:
	if is_status():
		return "%s %s -> %s %s %s x%d" % [Kind.keys()[kind], actor_id, target_id, skill_id, status_id, amount]
	return "%s %s -> %s %s %d (hp %d -> %d)" % [
		Kind.keys()[kind], actor_id, target_id, skill_id, amount, hp_before, hp_after]
