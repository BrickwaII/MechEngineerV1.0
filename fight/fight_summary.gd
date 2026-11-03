class_name FightSummary
extends RefCounted
## What a fight came to, tallied from its one combat log (Fight.events) and
## its units (combat rework S6): actions used, action tags, HP and grid
## capacity lost, energy spent, statuses applied, setups, combos and Staggers.
## The harness (S8), Battle Mode's fun metrics, personality (S17) and the
## post-fight presentation read it, so they all count the same things the
## same way.
##
##   var s := fight.summary()            # Fight.summary() = FightSummary.of(fight)
##   s.squad.action_uses                 # {"strike": 5, "wait": 1}
##   s.squad.combos, s.grid_cost, s.unit("ace").hp_lost()
##
## Counting rules (one place for all readers):
## - A decision is a SKILL or WAIT event (FightEvent.is_decision()); a
##   Staggered unit's lost turn (RECOVER) is not one.
## - action_uses: decisions by combat skill id, "wait" for a wait.
## - tag_uses: decisions by action tag (ActionTag.TAGS).
## - combos: hits that cashed in a setup (FightEvent.is_combo()).
## - setups: statuses put on an opponent. statuses_applied counts every
##   status put on by the unit, by status id, on any target.
## - staggers: plating broken by the unit.
## - damage_dealt / damage_taken: HP that HIT events took (reflected damage
##   counts for the reflecting unit); healed: HP restored to the unit.
## - hp_start is worked back from the log: hp_end + damage_taken - healed.

## A unit's tally, or a side's (the sum of its units').
class Tally:
	extends RefCounted
	## Unit id, or "squad" / "enemies" for a side.
	var id := ""
	## A Combatant.Side value.
	var side := 0
	var decisions := 0
	## Combat skill id (or "wait") -> decisions.
	var action_uses: Dictionary = {}
	## Action tag -> decisions carrying it.
	var tag_uses: Dictionary = {}
	var hp_start := 0
	var hp_end := 0
	var max_hp := 0
	var damage_dealt := 0
	var damage_taken := 0
	var healed := 0
	## Units down at the end.
	var downed := 0
	var energy_spent_milli := 0
	## Status id -> times this unit (or side) put it on.
	var statuses_applied: Dictionary = {}
	var setups := 0
	var combos := 0
	var staggers := 0

	func hp_lost() -> int:
		return maxi(0, hp_start - hp_end)

	func energy_spent() -> float:
		return float(energy_spent_milli) / Combatant.MILLI

	## Percent of the decisions that used `action_id` (rounded).
	func share_percent(action_id: String) -> int:
		return roundi(100.0 * action_uses.get(action_id, 0) / decisions) if decisions > 0 else 0

	## Percent of the decisions that carried `tag` (rounded).
	func tag_percent(tag: String) -> int:
		return roundi(100.0 * tag_uses.get(tag, 0) / decisions) if decisions > 0 else 0

	func add(other: Tally) -> void:
		decisions += other.decisions
		hp_start += other.hp_start
		hp_end += other.hp_end
		max_hp += other.max_hp
		damage_dealt += other.damage_dealt
		damage_taken += other.damage_taken
		healed += other.healed
		downed += other.downed
		energy_spent_milli += other.energy_spent_milli
		setups += other.setups
		combos += other.combos
		staggers += other.staggers
		FightSummary._add_counts(action_uses, other.action_uses)
		FightSummary._add_counts(tag_uses, other.tag_uses)
		FightSummary._add_counts(statuses_applied, other.statuses_applied)

	func to_dict() -> Dictionary:
		return {
			"id": id, "side": side, "decisions": decisions, "action_uses": FightSummary._sorted(action_uses),
			"tag_uses": FightSummary._sorted(tag_uses), "hp": [hp_start, hp_end, max_hp],
			"damage_dealt": damage_dealt, "damage_taken": damage_taken, "healed": healed, "downed": downed,
			"energy_spent_milli": energy_spent_milli, "statuses_applied": FightSummary._sorted(statuses_applied),
			"setups": setups, "combos": combos, "staggers": staggers,
		}


## A FightResult.Outcome value.
var outcome := 0
var timed_out := false
## Every decision, both sides (Fight.action_count).
var decisions := 0
var ticks := 0
## Grid capacity the fight drained (FightResult.grid_cost): base, defense
## level and the squad's energy spent.
var grid_cost := 0.0
## The player side's tally, and the enemies'.
var squad := Tally.new()
var enemies := Tally.new()
## One tally per unit, in roster order.
var units: Array[Tally] = []


## The summary of `fight` as it stands (call once it is over for the final one).
static func of(fight: Fight) -> FightSummary:
	var s := FightSummary.new()
	s.outcome = fight.outcome
	s.timed_out = fight.timed_out
	s.decisions = fight.action_count
	s.ticks = fight.timeline.current_tick
	s.grid_cost = fight.result().grid_cost
	s.squad.id = "squad"
	s.squad.side = Combatant.Side.PLAYER
	s.enemies.id = "enemies"
	s.enemies.side = Combatant.Side.ENEMY
	var by_id := {}
	for c in fight.combatants:
		var t := Tally.new()
		t.id = c.id
		t.side = c.side
		t.hp_end = c.hp
		t.max_hp = c.max_hp
		t.downed = 0 if c.is_alive() else 1
		t.energy_spent_milli = c.energy_spent_milli
		s.units.append(t)
		by_id[c.id] = t
	for e in fight.events:
		var actor: Tally = by_id.get(e.actor_id)
		var target: Tally = by_id.get(e.target_id)
		match e.kind:
			FightEvent.Kind.SKILL, FightEvent.Kind.WAIT:
				if actor != null and e.is_decision():
					actor.decisions += 1
					var use := "wait" if e.kind == FightEvent.Kind.WAIT else e.skill_id
					actor.action_uses[use] = actor.action_uses.get(use, 0) + 1
					for tag in e.tags:
						actor.tag_uses[tag] = actor.tag_uses.get(tag, 0) + 1
			FightEvent.Kind.HIT:
				if actor != null:
					actor.damage_dealt += e.amount
					if e.is_combo():
						actor.combos += 1
				if target != null:
					target.damage_taken += e.amount
			FightEvent.Kind.HEAL:
				if target != null:
					target.healed += e.amount
			FightEvent.Kind.STATUS_APPLIED:
				if actor != null:
					actor.statuses_applied[e.status_id] = actor.statuses_applied.get(e.status_id, 0) + 1
					if target != null and target.side != actor.side:
						actor.setups += 1
			FightEvent.Kind.STAGGER:
				if actor != null:
					actor.staggers += 1
	for t in s.units:
		t.hp_start = t.hp_end + t.damage_taken - t.healed
		if t.side == Combatant.Side.PLAYER:
			s.squad.add(t)
		else:
			s.enemies.add(t)
	return s


## The tally of unit `unit_id`, or null.
func unit(unit_id: String) -> Tally:
	for t in units:
		if t.id == unit_id:
			return t
	return null


func is_victory() -> bool:
	return outcome == FightResult.Outcome.VICTORY


## Every field, with dictionaries in key order, for comparing and writing out.
func to_dict() -> Dictionary:
	return {
		"outcome": FightResult.Outcome.keys()[outcome].to_lower(), "timed_out": timed_out,
		"decisions": decisions, "ticks": ticks, "grid_cost": grid_cost, "squad": squad.to_dict(),
		"enemies": enemies.to_dict(), "units": units.map(func(t: Tally) -> Dictionary: return t.to_dict()),
	}


## A short readable block: outcome, then one line per side.
func text() -> String:
	var lines := PackedStringArray()
	lines.append("%s after %d decisions, %d ticks, grid cost %s" % [
		FightResult.Outcome.keys()[outcome].to_lower(), decisions, ticks, TextFormat.short_number(grid_cost)])
	for t: Tally in [squad, enemies]:
		lines.append("%s: %d decisions, HP -%d of %d, dealt %d, energy %s, uses %s, tags %s, setups %d, combos %d, staggers %d" % [
			t.id, t.decisions, t.hp_lost(), t.hp_start, t.damage_dealt, TextFormat.short_number(t.energy_spent()),
			_counts_text(t.action_uses), _counts_text(t.tag_uses), t.setups, t.combos, t.staggers])
	return "\n".join(lines)


static func _add_counts(into: Dictionary, from: Dictionary) -> void:
	for k: String in from:
		into[k] = into.get(k, 0) + int(from[k])


static func _sorted(counts: Dictionary) -> Dictionary:
	var keys := counts.keys()
	keys.sort()
	var out := {}
	for k: String in keys:
		out[k] = counts[k]
	return out


## "strike=5 wait=1", keys in alphabetical order; "-" when empty.
static func _counts_text(counts: Dictionary) -> String:
	if counts.is_empty():
		return "-"
	var parts := PackedStringArray()
	for k: String in _sorted(counts):
		parts.append("%s=%d" % [k, int(counts[k])])
	return " ".join(parts)
