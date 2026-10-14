class_name BattleReadout
extends RefCounted
## The numbers the battle screen draws on its arrows and meters, worked out
## from the fight without changing it. Needs no scene.
##
##   var badges := BattleReadout.intent_badges(fight, telegraph.tracker.current, rules)
##   var mine := BattleReadout.choice_badges(fight, action, choice)
##   var next := BattleReadout.compare(badges, BattleReadout.intent_badges(copy, choice.intents_after, rules))
##
## Every number is the one the fight resolves: tests/fight/preview/
## preview_matches_resolution_test.gd checks them over many seeded fights.


## One badge per arrow of every intent in `intents` (unit id -> UnitIntent), in
## roster order. A skill that hits every opponent gets one arrow per opponent,
## each with its own damage.
static func intent_badges(fight: Fight, intents: Dictionary, rules: PreviewRules = null) -> Array[ArrowBadge]:
	var out: Array[ArrowBadge] = []
	for c in fight.combatants:
		var intent: UnitIntent = intents.get(c.id)
		if intent == null or not c.is_alive():
			continue
		out.append_array(badges_for_intent(fight, intent, rules))
	return out


static func badges_for_intent(fight: Fight, intent: UnitIntent, rules: PreviewRules = null) -> Array[ArrowBadge]:
	var out: Array[ArrowBadge] = []
	var unit := fight.combatant(intent.unit_id)
	var skill := unit.skill(intent.skill_id()) if unit != null else null
	var target := fight.combatant(intent.target_id())
	if unit == null or skill == null or target == null:
		return out
	var random := rules != null and rules.is_random(skill.id)
	if intent.kind == UnitIntent.Kind.HEAL:
		var heal := ArrowBadge.new(unit.id, target.id, ArrowBadge.HEAL, skill.id,
			PreviewValue.unknown() if random else PreviewValue.of(intent.amount))
		out.append(heal)
		return out
	if skill.is_guard():
		out.append(ArrowBadge.new(unit.id, target.id, ArrowBadge.GUARD, skill.id,
			PreviewValue.unknown() if random else PreviewValue.of(maxi(target.guard_percent, skill.power_percent))))
		return out
	var kind := ArrowBadge.WAIT if intent.kind == UnitIntent.Kind.WAIT else ArrowBadge.ATTACK
	var bonus := WaitRules.damage_bonus_percent(unit.is_waiting() or intent.kind == UnitIntent.Kind.WAIT, fight.tuning)
	var targets: Array[Combatant] = [target]
	if skill.hits_all():
		targets = fight.opponents_of(unit)
	for t in targets:
		out.append(hit_badge(unit, t, skill, kind, bonus, fight.tuning, random))
	return out


## A badge for `attacker` hitting `target` with `skill`: the hp it would take
## (capped at the target's hp) and whether that downs it.
static func hit_badge(attacker: Combatant, target: Combatant, skill: CombatSkill, kind: String,
		bonus_percent: int, tuning: CombatTuning, random := false) -> ArrowBadge:
	if random:
		return ArrowBadge.new(attacker.id, target.id, kind, skill.id, PreviewValue.unknown())
	var dmg := mini(target.hp, DamageRules.damage_to(attacker, target, skill, tuning, bonus_percent))
	var badge := ArrowBadge.new(attacker.id, target.id, kind, skill.id, PreviewValue.of(dmg))
	badge.knocks_out = dmg >= target.hp
	return badge


## The arrows of the pending unit's own choice, from its preview: one per unit
## it hurts, heals or guards. Empty for a refused choice or a wait.
static func choice_badges(fight: Fight, action: FightAction, choice: ChoicePreview) -> Array[ArrowBadge]:
	var out: Array[ArrowBadge] = []
	var actor := fight.pending_actor
	if actor == null or action == null or choice == null or not choice.is_allowed() or action.kind != FightAction.Kind.SKILL:
		return out
	var skill := actor.skill(action.skill_id)
	if skill.is_guard():
		var target := fight.combatant(action.target_id)
		var percent: int = choice.guard_changes.get(target.id, target.guard_percent)
		out.append(ArrowBadge.new(actor.id, target.id, ArrowBadge.GUARD, skill.id, PreviewValue.of(percent)))
		return out
	for e in choice.effects:
		if e.damage.is_unknown():
			out.append(ArrowBadge.new(actor.id, e.unit_id, ArrowBadge.HEAL if skill.is_heal() else ArrowBadge.ATTACK,
				skill.id, PreviewValue.unknown()))
			continue
		if e.damage.value < 0:
			out.append(ArrowBadge.new(actor.id, e.unit_id, ArrowBadge.HEAL, skill.id, PreviewValue.of(-e.damage.value)))
		else:
			var badge := ArrowBadge.new(actor.id, e.unit_id, ArrowBadge.ATTACK, skill.id, e.damage)
			badge.knocks_out = e.would_go_down()
			out.append(badge)
	if out.is_empty() and skill.is_heal():
		# A heal on a unit at full hp still points at it, for +0.
		out.append(ArrowBadge.new(actor.id, action.target_id, ArrowBadge.HEAL, skill.id, PreviewValue.of(0)))
	return out


## `after` with each badge marked changed when `before` had no such arrow or a
## different amount or KO. Changes `after` in place and returns it.
static func compare(before: Array[ArrowBadge], after: Array[ArrowBadge]) -> Array[ArrowBadge]:
	for b in after:
		var old: ArrowBadge = null
		for a in before:
			if a.same_arrow(b):
				old = a
				break
		if old == null:
			b.changed = true
		elif not old.amount.equals(b.amount) or old.knocks_out != b.knocks_out:
			b.changed = true
			b.old_amount = old.amount
	return after


## The energy `actor` would have right after paying for `skill`.
@warning_ignore("integer_division")
static func energy_after(actor: Combatant, skill: CombatSkill) -> int:
	return maxi(0, actor.energy_milli - skill.energy_cost_milli()) / Combatant.MILLI


## The NEXT bar if the pending unit made the previewed choice: the unit acting
## now first, then the order once the choice resolves. Empty when the choice
## carries no order.
static func order_with_choice(current: Array[TimelineEntry], choice: ChoicePreview) -> Array[TimelineEntry]:
	var out: Array[TimelineEntry] = []
	if choice == null or choice.order_after.is_empty() or current.is_empty():
		return out
	out.append(current[0])
	for e in choice.order_after:
		if out.size() >= current.size():
			break
		out.append(e)
	return out


## True when two orders list the same units in the same slots.
static func same_order(a: Array[TimelineEntry], b: Array[TimelineEntry]) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i].combatant_id != b[i].combatant_id or a[i].ends_wait != b[i].ends_wait:
			return false
	return true
