class_name TimelineOps
extends RefCounted
## Timeline operations other rules call to move a unit on the ATB timeline
## (combat rework S2). Kept in its own module so the rules that call it
## (S4 Stagger, S11 Delay, S14 Overdraw) need not edit Timeline or Fight.
##
##   TimelineOps.delay(fight, foe, TimelineOps.turn_gauge(30, fight.tuning), actor)
##   TimelineOps.advance(fight, ally, TimelineOps.turn_gauge(50, fight.tuning), actor)
##   TimelineOps.knockback(fight, foe, TimelineOps.turn_gauge(40, fight.tuning), actor)
##
## Amounts are raw gauge. Data names them in percent of a turn (the units of
## combat_tuning.json timeline.action_threshold: 100 is one whole turn), and
## turn_gauge() scales that to the turn threshold the speed-range switch sets,
## so "30" means the same share of a turn under every speed rule.
##
## Gauge may go below 0: a unit pushed back that far fills the debt first.
## Every move raises a FightEvent (DELAY, ADVANCE, KNOCKBACK, RECOVERY) whose
## amount is the gauge moved; a move of 0 raises none.
##
## A waiting unit holds a full gauge and acts when its wait ends, so a delay
## or knockback cannot land on it at once: it is held (Combatant.held_delay)
## and paid when the unit next finishes an action. advance() cannot shorten a
## wait; it only cancels held delay. TODO(decision: wait-delay).


## Gauge for `percent_of_turn` (100 = one whole turn) under `tuning`'s turn
## threshold, rounded down.
@warning_ignore("integer_division")
static func turn_gauge(percent_of_turn: int, tuning: CombatTuning) -> int:
	return maxi(0, percent_of_turn) * tuning.turn_threshold() / maxi(1, tuning.action_threshold)


## Gauge `skill` costs after acting, on top of the turn threshold. 0 under
## the action-recovery switch's old option (none).
static func recovery_gauge(skill: CombatSkill, tuning: CombatTuning) -> int:
	if skill == null:
		return 0
	if tuning.variants != null and tuning.variants.is_chosen(FightVariants.ACTION_RECOVERY, FightVariants.RECOVERY_NONE):
		return 0
	return turn_gauge(skill.recovery, tuning)


## Pushes `unit` back by `gauge`. Returns the gauge moved.
static func delay(fight: Fight, unit: Combatant, gauge: int, by: Combatant = null) -> int:
	return _push_back(fight, unit, gauge, by, FightEvent.Kind.DELAY)


## Pushes `unit` back by `gauge` as a hit's knockback (S4's Stagger). The same
## move as delay(), reported as a KNOCKBACK.
static func knockback(fight: Fight, unit: Combatant, gauge: int, by: Combatant = null) -> int:
	return _push_back(fight, unit, gauge, by, FightEvent.Kind.KNOCKBACK)


## Moves `unit` forward by `gauge`, never past the turn threshold (a unit
## already full stays as it is), so it acts sooner but never twice for one
## fill. On a waiting unit it only cancels held delay. Returns the gauge moved.
static func advance(fight: Fight, unit: Combatant, gauge: int, by: Combatant = null) -> int:
	if unit == null or not unit.is_alive() or gauge <= 0:
		return 0
	var before := unit.gauge
	var moved := advance_gauge(unit, gauge, fight.timeline.threshold)
	_report(fight, FightEvent.Kind.ADVANCE, unit, by, moved, before)
	return moved


## Called by Fight right after `actor` finished using `skill`: the action's
## recovery pushes it back. Raises RECOVERY when the action has any.
static func recover(fight: Fight, actor: Combatant, skill: CombatSkill) -> int:
	return _push_back(fight, actor, recovery_gauge(skill, fight.tuning), actor, FightEvent.Kind.RECOVERY, skill)


## The move delay() and knockback() make, on `unit` alone with no event: for
## previews and simulations that hold no Fight.
static func push_back_gauge(unit: Combatant, gauge: int) -> int:
	if unit == null or not unit.is_alive() or gauge <= 0:
		return 0
	if unit.is_waiting():
		unit.held_delay += gauge
	else:
		unit.gauge -= gauge
	return gauge


## The move advance() makes, on `unit` alone with no event.
static func advance_gauge(unit: Combatant, gauge: int, threshold: int) -> int:
	if unit == null or not unit.is_alive() or gauge <= 0:
		return 0
	if unit.is_waiting():
		var cancelled := mini(gauge, unit.held_delay)
		unit.held_delay -= cancelled
		return cancelled
	var target := mini(unit.gauge + gauge, maxi(unit.gauge, threshold))
	var moved := target - unit.gauge
	unit.gauge = target
	return moved


static func _push_back(fight: Fight, unit: Combatant, gauge: int, by: Combatant, kind: FightEvent.Kind,
		skill: CombatSkill = null) -> int:
	var before := unit.gauge if unit != null else 0
	var moved := push_back_gauge(unit, gauge)
	_report(fight, kind, unit, by, moved, before, skill)
	return moved


static func _report(fight: Fight, kind: FightEvent.Kind, unit: Combatant, by: Combatant, moved: int,
		gauge_before: int, skill: CombatSkill = null) -> void:
	if moved <= 0 or fight == null:
		return
	var e := FightEvent.new(kind, fight.action_count, by.id if by != null else "", unit.id,
		skill.id if skill != null else "")
	e.amount = moved
	e.gauge_before = gauge_before
	e.gauge_after = unit.gauge
	e.hp_before = unit.hp
	e.max_hp = unit.max_hp
	fight.raise_event(e)
	fight.log_lines.append("  %s %s %d gauge (%d -> %d%s)" % [
		unit.display_name, _verb(kind), moved, gauge_before, unit.gauge,
		", held until its wait ends" if unit.is_waiting() and kind != FightEvent.Kind.ADVANCE else ""])


static func _verb(kind: FightEvent.Kind) -> String:
	match kind:
		FightEvent.Kind.ADVANCE:
			return "advances"
		FightEvent.Kind.KNOCKBACK:
			return "is knocked back"
		FightEvent.Kind.RECOVERY:
			return "recovers"
	return "is delayed"
