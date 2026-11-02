class_name Fight
extends RefCounted
## One fight as pure logic, in ATB wait mode: time runs until a unit is ready,
## then stops until that unit's action is submitted. Nothing moves mid-choice.
##
##   var unit := fight.advance()      # ticks until someone is ready, then pauses
##   fight.submit(FightAction.use("strike", target.id))
##   ...repeat until fight.is_over()
##
## A Staggered unit (StaggerRules) gets no decision: when its turn comes,
## advance() spends it recovering and runs on to the next unit.
##
## Deterministic: the same request, seed and decisions give the same fight.
## The seed only picks which enemies appear; nothing else is random.

var request: FightRequest
var fight_seed: int
var tuning: CombatTuning
var enemy_table: EnemyTable
var combatants: Array[Combatant] = []
var timeline: Timeline
## Applies, consumes and expires the units' statuses (Exposed). The state is
## on each Combatant; see StatusManager.
var statuses: StatusManager
## The unit waiting for a decision, or null while time runs or after the end.
var pending_actor: Combatant
var action_count := 0
var outcome := FightResult.Outcome.DEFEAT
var timed_out := false
## One tag per decision: "<unit id>:<skill id>" or "<unit id>:wait".
var action_tags: Array[String] = []
## One full record per decision, in order, with behaviour labels. Read by
## fight/post_fight/. See ActionTag.
var decision_tags: Array[ActionTag] = []
var log_lines: PackedStringArray = []
## The FightEvents of the latest action, in order. See FightEvent.
var last_events: Array[FightEvent] = []

## Raised for every FightEvent as an action resolves, for the presentation.
## Listening changes nothing in the fight.
signal event_raised(event: FightEvent)

var _over := false
## Why the request cannot be fought, or "" when it can.
var _invalid_reason := ""


func _init(p_request: FightRequest, p_seed: int, p_tuning: CombatTuning = null, p_enemy_table: EnemyTable = null) -> void:
	request = p_request
	fight_seed = p_seed
	tuning = p_tuning if p_tuning != null else CombatTuning.load_default()
	enemy_table = p_enemy_table if p_enemy_table != null else EnemyTable.load_default()
	statuses = StatusManager.new(tuning.statuses)
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed
	if not request.is_valid():
		_invalid_reason = "invalid request"
	elif not enemy_table.has_level(request.defense_level):
		_invalid_reason = "no enemy table entry for defense level %d" % request.defense_level
	else:
		_build_roster(rng)
	timeline = Timeline.new(combatants, tuning.turn_threshold())
	_log("fight start: %s level %d, seed %d" % [
		FightRequest.Kind.keys()[request.kind].to_lower(), request.defense_level, fight_seed])
	for c in combatants:
		_log("  %s %s (%s): hp %d, atk %d, def %d, spd %d, energy %d/%d" % [
			"ally " if c.side == Combatant.Side.PLAYER else "enemy", c.display_name, c.id,
			c.hp, c.stats.attack, c.stats.defense, c.stats.speed, c.energy(), c.stats.battery_capacity])
		if c.max_plating > 0:
			_log("    plating %d%s" % [
				c.max_plating, ", weak to %s" % c.plating_weakness if not c.plating_weakness.is_empty() else ""])
	_check_end()


## Runs time until a unit is ready and returns it; the fight then waits for
## submit(). Returns the same unit, with no time passing, while a decision is
## pending. Returns null once the fight is over. A Staggered unit's turn is
## spent recovering on the way (its RECOVER event becomes last_events).
func advance() -> Combatant:
	if _over:
		return null
	if pending_actor != null:
		return pending_actor
	pending_actor = timeline.advance_to_next_ready()
	while pending_actor != null and pending_actor.staggered:
		_recover(pending_actor)
		pending_actor = timeline.advance_to_next_ready()
	return pending_actor


func is_awaiting_decision() -> bool:
	return pending_actor != null


func is_over() -> bool:
	return _over


## Why `action` is not allowed for the pending unit, or "" when it is.
func check_action(action: FightAction) -> String:
	if _over:
		return "the fight is over"
	if pending_actor == null:
		return "no unit is waiting for a decision"
	if action == null:
		return "no action"
	var skill := pending_actor.skill(action.skill_id)
	if skill == null:
		return "%s has no skill %s" % [pending_actor.id, action.skill_id]
	if action.kind == FightAction.Kind.WAIT:
		var length_problem := WaitRules.check_wait_ticks(action.wait_ticks, tuning)
		if not length_problem.is_empty():
			return length_problem
		if action.wait_ticks == 0 and skill.energy_cost_milli() > pending_actor.max_energy_milli:
			return "%s can never afford %s" % [pending_actor.id, action.skill_id]
		return ""
	if not pending_actor.can_afford(skill):
		return "%s cannot afford %s" % [pending_actor.id, action.skill_id]
	var target := combatant(action.target_id)
	if target == null or not target.is_alive():
		return "no living target %s" % action.target_id
	match skill.target:
		CombatSkill.TARGET_SELF:
			if target != pending_actor:
				return "%s may only use %s on itself" % [pending_actor.id, action.skill_id]
		CombatSkill.TARGET_ALLY:
			if target.side != pending_actor.side:
				return "%s may not use %s on an opponent" % [pending_actor.id, action.skill_id]
		_:
			if target.side == pending_actor.side:
				return "%s may not target an ally" % pending_actor.id
	return ""


## Resolves the pending unit's action and resumes time. Returns "" on success,
## else the reason it was refused; a refused action changes nothing.
func submit(action: FightAction) -> String:
	var problem := check_action(action)
	if not problem.is_empty():
		return problem
	var actor := pending_actor
	pending_actor = null
	action_count += 1
	last_events = []
	var tag := ActionTag.begin(self, actor, action)
	if action.kind == FightAction.Kind.WAIT:
		_resolve_wait(actor, action)
	else:
		_resolve_skill(actor, action)
	tag.finish(self)
	decision_tags.append(tag)
	if not tag.labels.is_empty():
		log_lines.append("  tags: %s" % ", ".join(tag.labels))
	_check_end()
	return ""


func combatant(id: String) -> Combatant:
	for c in combatants:
		if c.id == id:
			return c
	return null


func living(side: Combatant.Side) -> Array[Combatant]:
	var out: Array[Combatant] = []
	out.assign(combatants.filter(func(c: Combatant) -> bool: return c.side == side and c.is_alive()))
	return out


func opponents_of(unit: Combatant) -> Array[Combatant]:
	return living(Combatant.Side.ENEMY if unit.side == Combatant.Side.PLAYER else Combatant.Side.PLAYER)


## The next `count` actions in order. See Timeline.preview().
func upcoming(count: int) -> Array[TimelineEntry]:
	return timeline.preview(count)


func energy_spent_milli(side: Combatant.Side) -> int:
	var total := 0
	for c in combatants:
		if c.side == side:
			total += c.energy_spent_milli
	return total


## The contract record for the map. Only meaningful once the fight is over.
func result() -> FightResult:
	var spent := float(energy_spent_milli(Combatant.Side.PLAYER)) / Combatant.MILLI
	var grid := (
		tuning.grid_base_cost
		+ tuning.grid_cost_per_defense_level * request.defense_level
		+ tuning.grid_cost_per_energy_spent * spent)
	var rewards: Dictionary[String, int] = {}
	if outcome == FightResult.Outcome.VICTORY:
		rewards = enemy_table.rewards(request.defense_level)
	return FightResult.new(outcome, grid, rewards)


func log_text() -> String:
	return "\n".join(log_lines)


func _resolve_skill(actor: Combatant, action: FightAction) -> void:
	var skill := actor.skill(action.skill_id)
	var target := combatant(action.target_id)
	var energy_before := actor.energy()
	actor.spend(skill)
	action_tags.append("%s:%s" % [actor.id, skill.id])
	var used := _event(FightEvent.Kind.SKILL, actor, target, skill)
	used.amount = skill.energy_cost
	used.energy_before = energy_before
	used.energy_after = actor.energy()
	_raise(used)
	_on_unit_acts(actor)
	if skill.is_heal():
		var hp_before := target.hp
		target.hp += DamageRules.heal(actor.stats, target.hp, target.max_hp, skill)
		actor.finish_action(tuning.turn_threshold())
		var healed := _event(FightEvent.Kind.HEAL, actor, target, skill)
		healed.amount = target.hp - hp_before
		healed.hp_before = hp_before
		_raise(healed)
		_log("%s uses %s on %s: %d healed, hp %d -> %d, energy %d -> %d" % [
			actor.display_name, skill.display_name, target.display_name, target.hp - hp_before, hp_before,
			target.hp, energy_before, actor.energy()])
		# A Mega or Ultra heal also guards its target.
		if skill.heal_guard_percent > 0:
			target.guard_percent = maxi(target.guard_percent, skill.heal_guard_percent)
			var shielded := _event(FightEvent.Kind.GUARD, actor, target, skill)
			shielded.amount = target.guard_percent
			_raise(shielded)
			_log("%s's %s also guards %s: next hit %d%% blocked" % [
				actor.display_name, skill.display_name, target.display_name, target.guard_percent])
		_apply_status(actor, target, skill)
		return
	if skill.is_absorb():
		target.brace_absorb = maxi(target.brace_absorb, DamageRules.brace_absorb(actor.stats, skill))
		actor.finish_action(tuning.turn_threshold())
		var braced := _event(FightEvent.Kind.BRACE, actor, target, skill)
		braced.amount = target.brace_absorb
		_raise(braced)
		_log("%s uses %s on %s: absorbs %d damage until its next action, energy %d -> %d" % [
			actor.display_name, skill.display_name, target.display_name, target.brace_absorb,
			energy_before, actor.energy()])
		return
	if skill.is_guard():
		target.guard_percent = maxi(target.guard_percent, skill.power_percent)
		target.reflect_percent = maxi(target.reflect_percent, skill.reflect_percent)
		actor.finish_action(tuning.turn_threshold())
		var guarded := _event(FightEvent.Kind.GUARD, actor, target, skill)
		guarded.amount = target.guard_percent
		_raise(guarded)
		_log("%s uses %s on %s: next hit %d%% blocked, energy %d -> %d" % [
			actor.display_name, skill.display_name, target.display_name, target.guard_percent,
			energy_before, actor.energy()])
		_apply_status(actor, target, skill)
		return
	var targets: Array[Combatant] = [target]
	if skill.hits_all():
		targets = opponents_of(actor)
	var bonus := WaitRules.damage_bonus_percent(actor.is_waiting(), tuning)
	var weakest := DamageRules.weakest(targets) if skill.weakest_bonus_percent > 0 else null
	actor.finish_action(tuning.turn_threshold())
	for t in targets:
		# Each hit of a multi-hit skill lands in turn; they stop once either
		# side is down.
		for i in maxi(1, skill.hit_count):
			if not t.is_alive() or not actor.is_alive():
				break
			_hit(actor, t, skill, energy_before, bonus + (skill.weakest_bonus_percent if t == weakest else 0))
		# A setup status goes on after the skill's own hits, so they do not use it up.
		_apply_status(actor, t, skill)


func _hit(actor: Combatant, target: Combatant, skill: CombatSkill, energy_before: int, bonus_percent := 0) -> void:
	var hp_before := target.hp
	var guarded := target.guard_percent
	var reflect := target.reflect_percent
	var b := DamagePipeline.run(actor.stats, target.stats, skill, tuning, bonus_percent, target)
	var dmg := b.final
	var unguarded := b.before_guard
	var absorbed := b.absorbed
	target.brace_absorb -= absorbed
	target.hp = maxi(0, target.hp - dmg)
	target.guard_percent = 0
	target.reflect_percent = 0
	ElasticityRules.after_hit(target, dmg, tuning)
	var extras := ""
	if b.status_percent > 0:
		var names := PackedStringArray()
		for id in b.status_ids:
			names.append(statuses.name_of(id))
		extras += " (+%d%% %s)" % [b.status_percent, ", ".join(names)]
	if b.payoff_percent > 0:
		extras += " (+%d%% payoff)" % b.payoff_percent
	if b.stagger_bonus_percent > 0:
		extras += " (+%d%% Staggered)" % b.stagger_bonus_percent
	if guarded > 0:
		extras += " (%d%% blocked)" % guarded
	if absorbed > 0:
		extras += " (%d absorbed, %d left)" % [absorbed, target.brace_absorb]
	_log("%s uses %s on %s: %d damage%s, hp %d -> %d, energy %d -> %d" % [
		actor.display_name, skill.display_name, target.display_name, dmg,
		extras, hp_before, target.hp, energy_before, actor.energy()])
	var hit := _event(FightEvent.Kind.HIT, actor, target, skill)
	hit.amount = hp_before - target.hp
	hit.blocked_percent = guarded
	hit.status_bonus_percent = b.status_percent
	hit.payoff_bonus_percent = b.payoff_percent
	hit.absorbed = absorbed
	hit.hp_before = hp_before
	_raise(hit)
	if not target.is_alive():
		_log("%s is down" % target.display_name)
		_raise(_event(FightEvent.Kind.DOWN, actor, target, skill))
	for used in statuses.consume_after_hit(target, skill):
		_status_event(FightEvent.Kind.STATUS_CONSUMED, actor, target, skill, used)
		_log("%s's %s is used up" % [target.display_name, statuses.name_of(used.status_id)])
	if target.is_alive() and target.plating > 0:
		_strip_plating(actor, target, skill)
	# A Mega or Ultra guard sends part of what it blocked back.
	@warning_ignore("integer_division")
	var back := maxi(0, unguarded - b.after_guard) * reflect / 100 if guarded > 0 else 0
	if back > 0 and actor.is_alive():
		var actor_hp := actor.hp
		actor.hp = maxi(0, actor.hp - back)
		_log("%s reflects %d damage to %s, hp %d -> %d" % [
			target.display_name, actor_hp - actor.hp, actor.display_name, actor_hp, actor.hp])
		var reflected := _event(FightEvent.Kind.HIT, target, actor, skill)
		reflected.amount = actor_hp - actor.hp
		reflected.hp_before = actor_hp
		_raise(reflected)
		if not actor.is_alive():
			_log("%s is down" % actor.display_name)
			_raise(_event(FightEvent.Kind.DOWN, target, actor, skill))


## Every hit takes plating off a plated unit; at zero it is Staggered.
func _strip_plating(actor: Combatant, target: Combatant, skill: CombatSkill) -> void:
	var pips := mini(target.plating, tuning.stagger.pips_stripped(skill.damage_type, target.plating_weakness))
	if pips <= 0:
		return
	target.plating -= pips
	var stripped := _event(FightEvent.Kind.PLATING, actor, target, skill)
	stripped.amount = pips
	stripped.plating_after = target.plating
	_raise(stripped)
	_log("%s's plating loses %d: %d of %d left" % [target.display_name, pips, target.plating, target.max_plating])
	if target.plating == 0:
		_stagger(actor, target, skill)


## Broken plating: the unit's wind-up is cancelled, it is knocked back, and it
## takes bonus damage until its next turn, which it spends recovering.
## TODO(decision: stagger-intent): the lost turn stands in for "cancel the
## intent" until S5 makes intents committed.
func _stagger(actor: Combatant, target: Combatant, skill: CombatSkill) -> void:
	target.staggered = true
	var was_waiting := target.is_waiting()
	target.cancel_wait()
	var lost := timeline.knockback(target, tuning.stagger.knockback_gauge(target.stats, timeline.threshold, tuning))
	var staggered := _event(FightEvent.Kind.STAGGER, actor, target, skill)
	staggered.amount = lost
	staggered.plating_after = target.plating
	_raise(staggered)
	_log("%s is Staggered%s: knocked back %d, its next turn is lost, hits on it deal +%d%%" % [
		target.display_name, " (its wait is cancelled)" if was_waiting else "", lost,
		tuning.stagger.damage_bonus_percent])


## A Staggered unit's turn: no decision, the Stagger ends and its plating
## comes back (StaggerRules.recover_percent).
func _recover(unit: Combatant) -> void:
	last_events = []
	_end_brace(unit)
	unit.staggered = false
	var before := unit.plating
	unit.plating = maxi(unit.plating, tuning.stagger.recovered_plating(unit.max_plating))
	unit.finish_action(timeline.threshold)
	var recovered := _event(FightEvent.Kind.RECOVER, unit, unit, null)
	recovered.amount = unit.plating - before
	recovered.plating_after = unit.plating
	_raise(recovered)
	_log("%s recovers from the Stagger: plating %d of %d" % [unit.display_name, unit.plating, unit.max_plating])


## A Brace lasts until its holder's next action: called as that action begins.
func _end_brace(unit: Combatant) -> void:
	if unit.brace_absorb <= 0:
		return
	var ended := _event(FightEvent.Kind.BRACE_END, unit, unit, null)
	ended.amount = unit.brace_absorb
	unit.brace_absorb = 0
	_raise(ended)
	_log("%s's Brace ends (%d unused)" % [unit.display_name, ended.amount])


func _resolve_wait(actor: Combatant, action: FightAction) -> void:
	var skill := actor.skill(action.skill_id)
	var energy_before := actor.energy()
	actor.begin_wait(skill.energy_cost_milli(), action.wait_ticks)
	actor.energy_milli = mini(actor.max_energy_milli, actor.energy_milli + WaitRules.start_bonus_milli(tuning))
	action_tags.append("%s:wait" % actor.id)
	var waited := _event(FightEvent.Kind.WAIT, actor, null, skill)
	waited.amount = action.wait_ticks
	waited.energy_before = energy_before
	waited.energy_after = actor.energy()
	_raise(waited)
	_on_unit_acts(actor)
	if action.wait_ticks > 0:
		_log("%s waits %d ticks (energy %d, %s costs %d)" % [
			actor.display_name, action.wait_ticks, actor.energy(), skill.display_name, skill.energy_cost])
	else:
		_log("%s waits for %s (energy %d of %d)" % [
			actor.display_name, skill.display_name, actor.energy(), skill.energy_cost])


## `unit` begins an action: the statuses that last until its next action end.
## The timeline point "until the holder's next action" (StatusManager). Called
## right after the action's SKILL or WAIT event, before it changes anything.
## TODO(decision: status-expiry-wait): a wait counts as the holder's action.
func _on_unit_acts(unit: Combatant) -> void:
	_end_brace(unit)
	for gone in statuses.on_unit_acts(unit):
		_status_event(FightEvent.Kind.STATUS_EXPIRED, unit, unit, null, gone)
		_log("%s's %s wears off" % [unit.display_name, statuses.name_of(gone.status_id)])


## Puts `skill`'s applies_status on `target`, when it has one and the target
## is still up.
func _apply_status(actor: Combatant, target: Combatant, skill: CombatSkill) -> void:
	if skill.applies_status.is_empty():
		return
	var held := statuses.apply(target, skill.applies_status, actor.id, action_count)
	if held == null:
		return
	_status_event(FightEvent.Kind.STATUS_APPLIED, actor, target, skill, held)
	_log("%s is %s%s" % [target.display_name, statuses.name_of(held.status_id),
		" x%d" % held.stacks if held.stacks > 1 else ""])


func _status_event(kind: FightEvent.Kind, actor: Combatant, target: Combatant, skill: CombatSkill, status: StatusInstance) -> void:
	var e := _event(kind, actor, target, skill)
	e.status_id = status.status_id
	e.amount = status.stacks
	_raise(e)


func _check_end() -> void:
	if _over:
		return
	if not _invalid_reason.is_empty():
		_finish(FightResult.Outcome.DEFEAT, "no fight: " + _invalid_reason)
	elif living(Combatant.Side.PLAYER).is_empty():
		_finish(FightResult.Outcome.DEFEAT, "defeat")
	elif living(Combatant.Side.ENEMY).is_empty():
		_finish(FightResult.Outcome.VICTORY, "victory")
	elif action_count >= tuning.max_actions:
		timed_out = true
		_finish(FightResult.Outcome.DEFEAT, "defeat: action limit of %d reached" % tuning.max_actions)


@warning_ignore("integer_division")
func _finish(p_outcome: FightResult.Outcome, text: String) -> void:
	_over = true
	outcome = p_outcome
	pending_actor = null
	_log("%s after %d actions, energy spent by squad %d" % [
		text, action_count, energy_spent_milli(Combatant.Side.PLAYER) / Combatant.MILLI])


## A new event for the current action; hp fields read the target as it is now.
func _event(kind: FightEvent.Kind, actor: Combatant, target: Combatant, skill: CombatSkill) -> FightEvent:
	var e := FightEvent.new(kind, action_count, actor.id, target.id if target != null else "", skill.id if skill != null else "")
	e.skill_level = skill.level if skill != null else 1
	if target != null:
		e.hp_before = target.hp
		e.hp_after = target.hp
		e.max_hp = target.max_hp
	return e


func _raise(event: FightEvent) -> void:
	if event.target_id != "":
		event.hp_after = combatant(event.target_id).hp
	last_events.append(event)
	event_raised.emit(event)


func _log(text: String) -> void:
	log_lines.append("[t%04d] %s" % [timeline.current_tick if timeline != null else 0, text])


func _build_roster(rng: RandomNumberGenerator) -> void:
	var order := 0
	for member in request.squad:
		var hp := mini(member.hp, member.max_hp) if member.max_hp > 0 else member.hp
		if hp <= 0:
			continue
		combatants.append(Combatant.new(
			member.id, member.display_name, Combatant.Side.PLAYER, order, member.stats, hp,
			SquadSkills.ids_for(member, tuning), tuning, SquadSkills.overrides_for(member, tuning)))
		order += 1
	var picks := enemy_table.pick_for(request, rng, tuning.variants.option(FightVariants.ENEMY_FACTIONS), tuning)
	# A unit alone of its kind needs no number: "Precinct Overseer", but
	# "Rust Hound 1" and "Rust Hound 2".
	var totals := {}
	for enemy_id in picks:
		totals[enemy_id] = totals.get(enemy_id, 0) + 1
	var counts := {}
	for enemy_id in picks:
		counts[enemy_id] = counts.get(enemy_id, 0) + 1
		var stats := enemy_table.stats_for(enemy_id, request, tuning)
		var shown_name: String = enemy_table.name_of(enemy_id)
		if totals[enemy_id] > 1:
			shown_name = "%s %d" % [shown_name, counts[enemy_id]]
		var unit := Combatant.new(
			"%s#%d" % [enemy_id, counts[enemy_id]],
			shown_name,
			Combatant.Side.ENEMY, order, stats, stats.hp, enemy_table.skills_of(enemy_id), tuning)
		var archetype := enemy_table.archetype_for(enemy_id)
		if archetype != null and archetype.is_plated():
			unit.plating = archetype.plating
			unit.max_plating = archetype.plating
			unit.plating_weakness = archetype.plating_weakness
		combatants.append(unit)
		order += 1
