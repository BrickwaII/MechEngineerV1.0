class_name ChoiceReadout
extends RefCounted
## What the focused card says about a choice before it is made (combat rework
## S7), worked out on copies of the fight, never the fight itself:
##
## - landing(): where the bot lands on the timeline afterwards (its slot in
##   the projected order, FightPreview.project_turns(), and in how many
##   ticks), its Energy when that turn comes (what a Wait banks), and the
##   state right after the choice (for the timeline's marks).
## - combo_lines(): conditional combo bonuses, in words with real numbers:
##   "Then Ace's Heavy Strike: 18, 36 with Exposed (Ace acts 3rd)." for a
##   setup, "18 now. 36 if Rook Shreds it first (Rook acts 3rd)." for a
##   payoff without its setup, and what a hit does to plating.
##
## TODO(decision: recovery-projection): later turns assume every unit, the
## squad's other bots included, plays its current intent (IntentFightPolicy),
## as project_turns() does. The bot's own landing tick is exact unless
## something between now and then delays it.
##
##   var land := ChoiceReadout.landing(fight, FightAction.use("heavy_strike", "brute#1"), preview, 8)
##   land.slot   # 2: its next turn is the 3rd action after this one, the
##               # 4th chip of the AFTER bar (whose 1st is this action)
##   var lines := ChoiceReadout.combo_lines(fight, action, land.after, land.order, preview)


## {"order": the projected next turns (TimelineEntry), "slot": the 0-based
## index of the actor's next turn in it (-1 when not within `count`), "ticks":
## ticks from now to that turn (-1), "energy_now", "energy_at_turn": the
## actor's Energy when that turn comes (-1), "after": the fight right after
## the choice resolves (a copy; null when refused or over)}.
static func landing(fight: Fight, action: FightAction, preview: FightPreview, count: int) -> Dictionary:
	var actor := fight.pending_actor
	var out := {"order": [] as Array[TimelineEntry], "slot": -1, "ticks": -1,
		"energy_now": actor.energy() if actor != null else 0, "energy_at_turn": -1, "after": null}
	if actor == null or action == null or not fight.check_action(action).is_empty():
		return out
	var order := preview.project_turns(fight, action, count)
	out.order = order
	for i in order.size():
		if order[i].combatant_id == actor.id:
			out.slot = i
			out.ticks = order[i].tick - fight.timeline.current_tick
			break
	var copy := FightCopy.of(fight)
	copy.submit(action)
	if copy.is_over():
		return out
	out.after = FightCopy.of(copy)
	var at_turn := _play_to(copy, actor.id, preview, fight.fight_seed, maxi(count, 1) * 4)
	if at_turn != null:
		out.energy_at_turn = at_turn.combatant(actor.id).energy()
	return out


## Plays `copy` on (it is changed) as project_turns() plays it, every
## decision by IntentFightPolicy, until `unit_id` is the unit to act: returns
## the copy then, or null when that turn does not come within `limit`
## decisions.
static func _play_to(copy: Fight, unit_id: String, preview: FightPreview, fight_seed: int, limit: int) -> Fight:
	var player := IntentFightPolicy.new(preview.planner)
	var fallback := SimpleFightPolicy.new()
	var rng := HeadlessFightRunner.policy_rng(fight_seed)
	for n in limit:
		if copy.is_over():
			return null
		var unit := copy.advance()
		if unit == null:
			return null
		if unit.id == unit_id:
			return copy
		HeadlessFightRunner.play_turn(copy, unit, player, fallback, rng)
	return null


## Conditional combo lines for the pending actor's `action`. `after` and
## `order` are landing()'s. Empty when there is nothing to say.
static func combo_lines(fight: Fight, action: FightAction, after: Fight, order: Array, preview: FightPreview) -> Array[String]:
	var out: Array[String] = []
	var actor := fight.pending_actor
	if actor == null or action == null or action.kind != FightAction.Kind.SKILL:
		return out
	var skill := actor.skill(action.skill_id)
	var target := fight.combatant(action.target_id)
	if skill == null or target == null or not skill.is_damage() or target.side == actor.side:
		return out
	out.append_array(_payoff_lines(fight, actor, skill, target))
	if after != null:
		out.append_array(_setup_lines(fight, action, after, order, preview))
		out.append_array(_plating_lines(target, after.combatant(target.id)))
	return out


## What the actor's payoff action deals against its status, or {} when it
## has no payoff: {"status": name, "active": the target holds it now, "now":
## damage now, "combo": damage with the status ("plain" without it when
## active), "setter": the ally that can put it on ("" for none), "when": when
## that ally acts}.
static func payoff_combo(fight: Fight, actor: Combatant, skill: CombatSkill, target: Combatant) -> Dictionary:
	var status := skill.payoff_condition
	if status.is_empty() or skill.payoff_bonus_percent <= 0:
		return {}
	var bonus := _wait_bonus(actor, fight)
	var out := {"status": fight.statuses.name_of(status), "active": target.has_status(status),
		"now": DamagePipeline.total(actor, target, skill, fight.tuning, bonus), "setter": "", "when": ""}
	if out.active:
		var without := FightCopy.of(fight)
		var t := without.combatant(target.id)
		t.statuses.assign(t.statuses.filter(func(x: StatusInstance) -> bool: return x.status_id != status))
		out["combo"] = out.now
		out["plain"] = DamagePipeline.total(without.combatant(actor.id), t, skill, fight.tuning, bonus)
		return out
	var with_copy := FightCopy.of(fight)
	with_copy.statuses.apply(with_copy.combatant(target.id), status, actor.id, fight.action_count)
	out["combo"] = DamagePipeline.total(with_copy.combatant(actor.id), with_copy.combatant(target.id), skill, fight.tuning, bonus)
	var setter := _setter_for(fight, actor, status)
	if not setter.is_empty():
		out["setter"] = setter.name
		out["when"] = setter.when
	return out


static func _payoff_lines(fight: Fight, actor: Combatant, skill: CombatSkill, target: Combatant) -> Array[String]:
	var out: Array[String] = []
	var p := payoff_combo(fight, actor, skill, target)
	if p.is_empty():
		return out
	if p.active:
		out.append("Combo: %d against %s (%d without)." % [p.combo, p.status, p.plain])
	elif p.setter.is_empty():
		out.append("%d now. %d against %s." % [p.now, p.combo, p.status])
	else:
		out.append("%d now. %d if %s puts %s on first (%s)." % [p.now, p.combo, p.setter, p.status, p.when])
	return out


## The status the actor's action puts on, and the next projected turn that
## meets it, or {} when it puts none on (or the target goes down): {"status":
## name, "status_id", "slot": index in `order`, "wears_off": the target acts
## first (or the status is gone by the ally's turn), and otherwise the ally's
## hit: "unit_id", "skill_id", "plain" (its damage then without the status),
## "combo" (with it)}. The ally's hit is worked out on a copy played on to its
## turn, so a Stagger's lost turn or a recovery in between counts.
static func setup_combo(fight: Fight, action: FightAction, after: Fight, order: Array, preview: FightPreview) -> Dictionary:
	var actor := fight.pending_actor
	var skill := actor.skill(action.skill_id) if actor != null and action != null else null
	if skill == null or after == null or skill.applies_status.is_empty():
		return {}
	var status := skill.applies_status
	var t_after := after.combatant(action.target_id)
	if t_after == null or not t_after.is_alive() or not t_after.has_status(status):
		return {}
	var name := after.statuses.name_of(status)
	for i in order.size():
		var entry: TimelineEntry = order[i]
		var unit := after.combatant(entry.combatant_id)
		if unit == null or not unit.is_alive():
			continue
		if unit.id == t_after.id:
			return {"status": name, "status_id": status, "slot": i, "wears_off": true}
		if unit.side != actor.side:
			continue
		var then := _play_to(FightCopy.of(after), unit.id, preview, fight.fight_seed, i + 1)
		var t_then := then.combatant(t_after.id) if then != null else null
		if t_then == null or not t_then.is_alive() or not t_then.has_status(status):
			return {"status": name, "status_id": status, "slot": i, "wears_off": true}
		var x := then.combatant(unit.id)
		var best := _best_hit(then, x, t_then, status)
		if best.is_empty():
			continue
		t_then.statuses.assign(t_then.statuses.filter(func(s: StatusInstance) -> bool: return s.status_id != status))
		var plain := DamagePipeline.total(x, t_then, best.skill, fight.tuning, _wait_bonus(x, then))
		return {"status": name, "status_id": status, "slot": i, "wears_off": false, "unit_id": unit.id,
			"skill_id": best.skill.id, "combo": best.damage, "plain": plain}
	return {}


static func _setup_lines(fight: Fight, action: FightAction, after: Fight, order: Array, preview: FightPreview) -> Array[String]:
	var out: Array[String] = []
	var c := setup_combo(fight, action, after, order, preview)
	if c.is_empty():
		return out
	var target := fight.combatant(action.target_id)
	if c.wears_off:
		out.append("%s wears off as %s acts (%s), before an ally hits it." % [
			c.status, target.display_name, _ordinal_text(c.slot)])
		return out
	var unit := fight.combatant(c.unit_id)
	out.append("Then %s's %s: %d, %d with %s (%s acts %s)." % [
		unit.display_name, unit.skill(c.skill_id).display_name, c.plain, c.combo, c.status,
		unit.display_name, _ordinal_text(c.slot)])
	return out


## The hit `unit` would cash `status` in with: an action that pays off against
## it first, else its strongest damage action. {"skill", "damage"} or {}.
static func _best_hit(fight: Fight, unit: Combatant, target: Combatant, status: String) -> Dictionary:
	var best := {}
	for s in unit.skills():
		if not s.is_damage() or s.target == CombatSkill.TARGET_SELF or not s.applies_status.is_empty():
			continue
		var dmg := DamagePipeline.total(unit, target, s, fight.tuning, _wait_bonus(unit, fight))
		var pays := s.payoff_condition == status
		var better: bool = best.is_empty() or (pays and not best.pays) or (pays == best.pays and dmg > best.damage)
		if better:
			best = {"skill": s, "damage": dmg, "pays": pays}
	return best


## A hit on plating: pips it strips, or the Stagger it causes.
static func _plating_lines(before: Combatant, after: Combatant) -> Array[String]:
	var out: Array[String] = []
	if after == null or before.plating <= 0:
		return out
	if after.staggered and not before.staggered:
		var cancel := ""
		if before.committed != null:
			var hit := before.skill(before.committed.skill_id())
			cancel = " and drops its %s" % (hit.display_name if hit != null else "Wind-up")
		out.append("Breaks its Plating: Stagger! %s loses its next turn%s." % [before.display_name, cancel])
	elif after.plating < before.plating:
		out.append("Plating %d → %d." % [before.plating, after.plating])
	return out


## The ally (not `actor`) whose action puts `status` on, and when it acts:
## {"name", "when"} or {} for none.
static func _setter_for(fight: Fight, actor: Combatant, status: String) -> Dictionary:
	var upcoming := fight.upcoming(8)
	for c in fight.combatants:
		if c.side != actor.side or not c.is_alive():
			continue
		if c == actor:
			continue
		for s in c.skills():
			if s.applies_status == status:
				var when := "acts later"
				for i in upcoming.size():
					if upcoming[i].combatant_id == c.id:
						when = "acts %s" % BattleMath.ordinal(i + 1)
						break
				return {"name": c.display_name, "when": when}
	return {}


static func _wait_bonus(unit: Combatant, fight: Fight) -> int:
	return WaitRules.damage_bonus_percent(unit.is_waiting(), fight.tuning)


## Projected slot `i` (0: the next action after this one) as the AFTER bar
## numbers it, where the 1st chip is the action being chosen: "2nd", "3rd".
static func _ordinal_text(i: int) -> String:
	return BattleMath.ordinal(i + 2)


## The actor's landing slot in words, as the AFTER bar numbers it: "3rd, in
## 140 ticks". "" when it is not within the projection.
static func landing_text(land: Dictionary) -> String:
	if int(land.get("slot", -1)) < 0:
		return ""
	var ticks := int(land.ticks)
	return "%s, in %d tick%s" % [_ordinal_text(int(land.slot)), ticks, "" if ticks == 1 else "s"]


## The AFTER bar for `land` (landing()'s): the unit acting now first, then
## the projected order, as long as `current` (the NEXT bar). Empty without a
## projection.
static func after_bar(current: Array[TimelineEntry], land: Dictionary) -> Array[TimelineEntry]:
	var out: Array[TimelineEntry] = []
	var order: Array = land.get("order", [])
	if order.is_empty() or current.is_empty():
		return out
	out.append(current[0])
	for e: TimelineEntry in order:
		if out.size() >= current.size():
			break
		out.append(e)
	return out
