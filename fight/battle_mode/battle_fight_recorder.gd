class_name BattleFightRecorder
extends RefCounted
## Watches one fight from outside and measures what Battle Mode reports: the
## squad's turns, HP lost, energy spent and wasted, action uses, combos and
## Staggers. Turns, uses, HP, combos, setups and Staggers come from the
## fight's summary (FightSummary, read off the one combat log), so Battle
## Mode counts them exactly as the harness and post-fight do. Only wasted
## energy is its own measure, from combatant energy between actions. It
## changes nothing in the fight and needs no new fight state.
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

var _last_tick := 0
var _last_energy := {}
var _last_rate := {}
var _wasted_milli := 0


func _init(fight: Fight) -> void:
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
	var s := fight.summary()
	r.victory = s.is_victory()
	r.actions = s.decisions
	r.ticks = s.ticks
	r.hp_start = s.squad.hp_start
	r.hp_end = s.squad.hp_end
	r.hp_max = s.squad.max_hp
	r.bots_downed = s.squad.downed
	r.enemies_downed = s.enemies.downed
	r.energy_spent_milli = s.squad.energy_spent_milli
	r.energy_wasted_milli = _wasted_milli
	r.turns = s.squad.decisions
	r.action_uses = s.squad.action_uses.duplicate()
	r.combos = s.squad.combos
	r.setups = s.squad.setups
	r.staggers = s.squad.staggers
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
