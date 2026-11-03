class_name FightLog
extends RefCounted
## Reads the one combat log, Fight.events (combat rework S6): the decisions
## in it, one canonical line per event, and a replay. The log plus the fight's
## request and seed reproduce the fight exactly: the seed picks the enemies,
## and each decision event (FightEvent.is_decision()) holds the action as
## submitted. Nothing else is random (ground rule 3).
##
##   var again := FightLog.replay(fight.request, fight.fight_seed, fight.events)
##   assert(FightLog.lines(again.events) == FightLog.lines(fight.events))
##
## A fight built by hand (tests that swap units in after Fight.new) replays
## through replay_into() on a second fight built the same way.


## The decisions in `events`, in order: a copy of each submitted action.
static func decisions(events: Array[FightEvent]) -> Array[FightAction]:
	var out: Array[FightAction] = []
	for e in events:
		if e.is_decision():
			out.append(e.action.copy())
	return out


## The events `action_index` raised (the decision with that Fight.action_count,
## and anything raised after it before the next decision, such as RECOVER).
static func for_action(events: Array[FightEvent], action_index: int) -> Array[FightEvent]:
	var out: Array[FightEvent] = []
	for e in events:
		if e.action_index == action_index:
			out.append(e)
	return out


## The events of `kind`, in order.
static func of_kind(events: Array[FightEvent], kind: FightEvent.Kind) -> Array[FightEvent]:
	var out: Array[FightEvent] = []
	for e in events:
		if e.kind == kind:
			out.append(e)
	return out


## One line per event holding every field (FightEvent.to_dict()), for
## comparing two logs or writing one out.
static func lines(events: Array[FightEvent]) -> PackedStringArray:
	var out := PackedStringArray()
	for e in events:
		out.append(JSON.stringify(e.to_dict(), "", true))
	return out


## Plays `decisions` (or the decisions in a log: pass decisions(events)) into
## `fight`, a fresh fight built the way the original was, running time between
## them. Returns "" once every decision is played, else why one was refused
## ("decision 3 (strike on foe#1): ..."). Stops early if the fight ends.
static func replay_into(fight: Fight, p_decisions: Array[FightAction]) -> String:
	for i in p_decisions.size():
		if fight.advance() == null:
			return "the fight ended before decision %d (%s)" % [i + 1, p_decisions[i]]
		var problem := fight.submit(p_decisions[i].copy())
		if not problem.is_empty():
			return "decision %d (%s): %s" % [i + 1, p_decisions[i], problem]
	# Time runs on to the next decision (or the end), as the original did:
	# a Staggered unit's recovery after the last decision is part of the log.
	fight.advance()
	return ""


## A new fight from `request` and `seed_value` with the decisions in `events`
## played into it. Pass the original's tuning and enemy table when it had its
## own. A refused decision is pushed as an error and stops the replay.
static func replay(request: FightRequest, seed_value: int, events: Array[FightEvent],
		tuning: CombatTuning = null, enemy_table: EnemyTable = null) -> Fight:
	var fight := Fight.new(request, seed_value, tuning, enemy_table)
	var problem := replay_into(fight, decisions(events))
	if not problem.is_empty():
		push_error("FightLog.replay: " + problem)
	return fight
