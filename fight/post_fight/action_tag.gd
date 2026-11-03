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
##
## Action tags (combat rework S6) say what kind of play the decision was, for
## the harness, the fight summary, personality drift (S17) and the post-fight
## readout. A decision carries its action's own data tags (actions.json
## "tags", which must be names from TAGS) plus the ones its target and its
## outcome earn:
##   offense   a damage action
##   defense   a guard, Brace or heal
##   setup     put a status on an opponent
##   payoff    one of its hits cashed in a setup: a status bonus (Exposed)
##             or a payoff bonus (FightEvent.is_combo())
##   self      aimed at the actor itself
##   ally      aimed at another unit on the actor's side
##   reactive  answers an enemy intent: a hit on an opponent holding a
##             committed wind-up, or a defense on a unit an opponent's
##             intent attacks. Only archetype enemies hold intents in the
##             fight (S5), so only they can be answered.
##   banked    a wait: banks energy for a later turn
## TODO(decision: s6-tag-rules): these rules are S6's reading of the plan.
## Tags live apart from `labels`: labels print in the fight log and drive
## today's drift rules, tags do neither, so adding them changed no fight.
## A drift rule may name either (has_label()).

const HIT_ENEMY := "hit_enemy"
const SELF_TARGET := "self_target"
const ALLY_TARGET := "ally_target"
const WAIT := "wait"
const SOLO := "solo"
const FIRST_AFFORDABLE := "first_affordable"
const ALL_LABELS: Array[String] = [HIT_ENEMY, SELF_TARGET, ALLY_TARGET, WAIT, SOLO, FIRST_AFFORDABLE]
const OFFENSE := "offense"
const DEFENSE := "defense"
const SETUP := "setup"
const PAYOFF := "payoff"
const SELF := "self"
const ALLY := "ally"
const REACTIVE := "reactive"
const BANKED := "banked"
## Every action tag, in the order a decision lists them.
const TAGS: Array[String] = [OFFENSE, DEFENSE, SETUP, PAYOFF, SELF, ALLY, REACTIVE, BANKED]
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
## The decision's action tags, in TAGS order (see the class comment). Between
## begin() and finish() only the ones it has whatever happens (tags_before()).
var tags: Array[String] = []

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
	var skill := actor.skill(action.skill_id)
	tag.energy_cost_milli = skill.energy_cost_milli() if skill != null else 0
	if action.kind == FightAction.Kind.SKILL:
		tag.target_id = action.target_id
		var target := fight.combatant(action.target_id)
		if target != null:
			tag.target_side = target.side
			tag._target_hp_before = target.hp
	tag.tags = tags_before(fight, actor, action)
	return tag


## The tags `action` by `actor` has before it resolves: the action's data
## tags, offense or defense, self or ally, reactive, banked.
static func tags_before(fight: Fight, actor: Combatant, action: FightAction) -> Array[String]:
	var out: Array[String] = []
	if action.kind == FightAction.Kind.WAIT:
		out.append(BANKED)
		return out
	var skill := actor.skill(action.skill_id)
	var target := fight.combatant(action.target_id)
	if skill == null:
		return out
	out.append_array(skill.tags)
	if skill.is_damage():
		out.append(OFFENSE)
	else:
		out.append(DEFENSE)
	if target == null:
		return out
	if target == actor:
		out.append(SELF)
	elif target.side == actor.side:
		out.append(ALLY)
	if target.side != actor.side:
		if target.committed != null:
			out.append(REACTIVE)
	elif not skill.is_damage() and _is_attacked_by_intent(fight, target):
		out.append(REACTIVE)
	return out


## True when an opponent of `unit` holds an intent or a committed hit aimed at it.
static func _is_attacked_by_intent(fight: Fight, unit: Combatant) -> bool:
	for o in fight.opponents_of(unit):
		if o.committed != null and o.committed.target_id() == unit.id:
			return true
		if o.intent != null and o.intent.kind != UnitIntent.Kind.HEAL and o.intent.target_id() == unit.id:
			return true
	return false


## Records the outcome and the labels. `fight.decision_tags` must not hold
## this tag yet: the labels look back over the decisions before it.
func finish(fight: Fight) -> void:
	if kind == FightAction.Kind.SKILL:
		var target := fight.combatant(target_id)
		if target != null:
			damage = maxi(0, _target_hp_before - target.hp)
	labels = compute_labels(self, fight.decision_tags)
	tags = compute_tags(tags, actor_id, actor_side, fight.last_events, fight)


## The decision's tags: `before` (tags_before()) plus setup and payoff when
## `events`, the action's events, show `actor_id` putting a status on an
## opponent or landing a combo. In TAGS order, data tags outside TAGS last.
static func compute_tags(before: Array[String], p_actor_id: String, p_actor_side: int,
		events: Array[FightEvent], fight: Fight) -> Array[String]:
	var found := {}
	for t in before:
		found[t] = true
	for e in events:
		if e.actor_id != p_actor_id:
			continue
		if e.is_combo():
			found[PAYOFF] = true
		elif e.kind == FightEvent.Kind.STATUS_APPLIED:
			var target := fight.combatant(e.target_id)
			if target != null and target.side != p_actor_side:
				found[SETUP] = true
	var out: Array[String] = []
	for t in TAGS:
		if found.has(t):
			out.append(t)
	for t: String in found:
		if not t in TAGS:
			out.append(t)
	return out


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


## True when the decision earned `label`, a label or an action tag.
func has_label(label: String) -> bool:
	return label in labels or label in tags


func has_tag(tag: String) -> bool:
	return tag in tags


## The short form Fight.action_tags uses: "<actor>:<skill>" or "<actor>:wait".
func short_text() -> String:
	return "%s:%s" % [actor_id, "wait" if kind == FightAction.Kind.WAIT else skill_id]


func _to_string() -> String:
	return "#%d t%d %s [%s]" % [index, tick, short_text(), ", ".join(labels)]
