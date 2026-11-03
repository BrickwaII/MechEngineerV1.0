class_name BattleFightRecorder
extends RefCounted
## Watches one fight from outside and measures what Battle Mode reports: the
## squad's turns, HP lost, energy spent and wasted, action uses, combos and
## Staggers. Reads only the fight's public record (FightEvents, action tags,
## combatant energy), so it changes nothing and needs no new fight state.
##
##   var rec := BattleFightRecorder.new(fight)   # before the first submit()
##   ... after every successful fight.submit(): rec.after_action(fight)
##   var record := rec.finish(fight, encounter)
##
## Wasted energy is recharge lost to a full battery. Between two resolved
## actions only time passes: each squad bot recharges ticks x its rate (its
## wait rate while waiting), up to its capacity, and whatever went past the
## capacity is lost. Every other energy change happens inside an action, so
## the snapshot after it already holds it.
## TODO(S6): read Fight.events (the one combat log) once it lands, in place of
## listening to event_raised.

var _events: Array[FightEvent] = []
var _hp_start := {}
var _last_tick := 0
var _last_energy := {}
var _last_rate := {}
var _wasted_milli := 0


func _init(fight: Fight) -> void:
	for c in fight.combatants:
		if c.side == Combatant.Side.PLAYER:
			_hp_start[c.id] = c.hp
	_snapshot(fight)
	if fight.action_count == 0 and fight.timeline.current_tick > 0:
		# Attached after time ran to the first decision (a battle screen
		# builds its fight that way): count from the start, when every bot
		# held its starting energy and nobody was waiting.
		_last_tick = 0
		for c in fight.combatants:
			if c.side == Combatant.Side.PLAYER and c.is_alive():
				@warning_ignore("integer_division")
				_last_energy[c.id] = c.max_energy_milli * fight.tuning.starting_energy_percent / 100
				_last_rate[c.id] = c.recharge_milli
	fight.event_raised.connect(_events.append)


## Call after every resolved action (and before reading the record).
func after_action(fight: Fight) -> void:
	var ticks := fight.timeline.current_tick - _last_tick
	for c in fight.combatants:
		if c.side == Combatant.Side.PLAYER and _last_rate.has(c.id):
			# Recharge stops at the cap, so after `ticks` the bot holds
			# min(capacity, start + ticks x rate); the rest was lost.
			_wasted_milli += maxi(0, int(_last_energy[c.id]) + ticks * int(_last_rate[c.id]) - c.max_energy_milli)
	_snapshot(fight)


## The fight's record. Call once the fight is over (or to read it so far).
func finish(fight: Fight, encounter: BattleEncounter) -> BattleFightRecord:
	if _last_tick != fight.timeline.current_tick:
		after_action(fight)
	var r := BattleFightRecord.new()
	if encounter != null:
		r.fight_number = encounter.fight_number
		r.kind = BattleEncounter.kind_name(encounter.kind)
		r.enemy_ids = encounter.enemy_ids.duplicate()
		r.distinct_types = encounter.distinct_types()
	r.victory = fight.outcome == FightResult.Outcome.VICTORY
	r.actions = fight.action_count
	r.ticks = fight.timeline.current_tick
	for c in fight.combatants:
		if c.side == Combatant.Side.PLAYER:
			r.hp_start += int(_hp_start.get(c.id, c.hp))
			r.hp_end += c.hp
			r.hp_max += c.max_hp
			if not c.is_alive():
				r.bots_downed += 1
		elif not c.is_alive():
			r.enemies_downed += 1
	r.energy_spent_milli = fight.energy_spent_milli(Combatant.Side.PLAYER)
	r.energy_wasted_milli = _wasted_milli
	for tag in fight.action_tags:
		var unit := fight.combatant(tag.get_slice(":", 0))
		if unit == null or unit.side != Combatant.Side.PLAYER:
			continue
		var action := tag.get_slice(":", 1)
		r.action_uses[action] = r.action_uses.get(action, 0) + 1
		r.turns += 1
	for e in _events:
		var actor := fight.combatant(e.actor_id)
		if actor == null or actor.side != Combatant.Side.PLAYER:
			continue
		match e.kind:
			FightEvent.Kind.HIT:
				if e.status_bonus_percent > 0 or e.payoff_bonus_percent > 0:
					r.combos += 1
			FightEvent.Kind.STATUS_APPLIED:
				var target := fight.combatant(e.target_id)
				if target != null and target.side != actor.side:
					r.setups += 1
			FightEvent.Kind.STAGGER:
				r.staggers += 1
	return r


func _snapshot(fight: Fight) -> void:
	_last_tick = fight.timeline.current_tick
	for c in fight.combatants:
		if c.side != Combatant.Side.PLAYER:
			continue
		_last_energy[c.id] = c.energy_milli
		if c.is_alive():
			_last_rate[c.id] = c.wait_recharge_milli if c.is_waiting() else c.recharge_milli
		else:
			_last_rate.erase(c.id)
