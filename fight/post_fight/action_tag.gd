class_name ActionTag
extends RefCounted
## The record of one decision in a fight: who acted, what they chose, what it
## did, and the behaviour labels it earned. Fight keeps one per decision, in
## order, in Fight.decision_tags.
##
## Labels are plain facts about the decision. What each fact means for a
## personality lives in data/post_fight/post_fight.json, not here:
##   hit_enemy         a skill that damaged an enemy
##   self_target       a skill aimed at the actor itself
##   ally_target       a skill aimed at another unit on the actor's side
##   wait              a wait
##   solo              no other unit on the actor's side decided since the
##                     actor's own previous decision (never on a first decision)
##   first_affordable  a skill that costs energy, used on the actor's first
##                     turn able to afford it: the actor could not afford it
##                     at its previous decision, or this is its first decision.
##                     A turn that ends a wait never earns it; the wait was the plan.

const HIT_ENEMY := "hit_enemy"
const SELF_TARGET := "self_target"
const ALLY_TARGET := "ally_target"
const WAIT := "wait"
const SOLO := "solo"
const FIRST_AFFORDABLE := "first_affordable"
const ALL_LABELS: Array[String] = [HIT_ENEMY, SELF_TARGET, ALLY_TARGET, WAIT, SOLO, FIRST_AFFORDABLE]
## target_side when the decision has no target.
const NO_SIDE := -1

## Position of this decision in the fight, from 0.
var index: int
var tick: int
var actor_id: String
## A Combatant.Side value.
var actor_side: int
## A FightAction.Kind value.
var kind: int
var skill_id: String
var target_id: String
## A Combatant.Side value, or NO_SIDE.
var target_side: int = NO_SIDE
var damage := 0
var energy_before_milli: int
var energy_cost_milli: int
## True when this turn ends a wait.
var after_wait: bool
var labels: Array[String] = []

var _target_hp_before := 0


## Captures the state before `action` resolves. Call finish() after it resolves.
static func begin(fight: Fight, actor: Combatant, action: FightAction) -> ActionTag:
	var tag := ActionTag.new()
	tag.index = fight.decision_tags.size()
	tag.tick = fight.timeline.current_tick
	tag.actor_id = actor.id
	tag.actor_side = actor.side
	tag.kind = action.kind
	tag.skill_id = action.skill_id
	tag.energy_before_milli = actor.energy_milli
	tag.after_wait = actor.is_waiting()
	var skill := fight.tuning.skill(action.skill_id)
	tag.energy_cost_milli = skill.energy_cost_milli() if skill != null else 0
	if action.kind == FightAction.Kind.SKILL:
		tag.target_id = action.target_id
		var target := fight.combatant(action.target_id)
		if target != null:
			tag.target_side = target.side
			tag._target_hp_before = target.hp
	return tag


## Records the outcome and the labels. `fight.decision_tags` must not hold
## this tag yet: the labels look back over the decisions before it.
func finish(fight: Fight) -> void:
	if kind == FightAction.Kind.SKILL:
		var target := fight.combatant(target_id)
		if target != null:
			damage = maxi(0, _target_hp_before - target.hp)
	labels = compute_labels(self, fight.decision_tags)


## The labels `tag` earns, given every decision before it in `earlier`.
static func compute_labels(tag: ActionTag, earlier: Array[ActionTag]) -> Array[String]:
	var out: Array[String] = []
	if tag.kind == FightAction.Kind.WAIT:
		out.append(WAIT)
	elif tag.target_id == tag.actor_id:
		out.append(SELF_TARGET)
	elif tag.target_side == tag.actor_side:
		out.append(ALLY_TARGET)
	elif tag.target_side != NO_SIDE and tag.damage > 0:
		out.append(HIT_ENEMY)

	var previous_own: ActionTag = null
	var ally_acted_since := false
	for i in range(earlier.size() - 1, -1, -1):
		var other := earlier[i]
		if other.actor_id == tag.actor_id:
			previous_own = other
			break
		if other.actor_side == tag.actor_side:
			ally_acted_since = true
	if previous_own != null and not ally_acted_since:
		out.append(SOLO)

	if (tag.kind == FightAction.Kind.SKILL and tag.energy_cost_milli > 0 and not tag.after_wait
			and (previous_own == null or previous_own.energy_before_milli < tag.energy_cost_milli)):
		out.append(FIRST_AFFORDABLE)
	return out


func has_label(label: String) -> bool:
	return label in labels


## The short form Fight.action_tags uses: "<actor>:<skill>" or "<actor>:wait".
func short_text() -> String:
	return "%s:%s" % [actor_id, "wait" if kind == FightAction.Kind.WAIT else skill_id]


func _to_string() -> String:
	return "#%d t%d %s [%s]" % [index, tick, short_text(), ", ".join(labels)]
