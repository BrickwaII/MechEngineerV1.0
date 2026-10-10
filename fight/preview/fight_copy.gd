class_name FightCopy
extends RefCounted
## A throwaway copy of a fight for trying a choice out. Shares the request,
## tuning, enemy table and each unit's stats (none of which a fight changes);
## everything that changes while a fight runs is copied.


## A copy of `fight` mid-fight. Do not copy a fight that is over.
static func of(fight: Fight) -> Fight:
	var copy := Fight.new(fight.request, fight.fight_seed, fight.tuning, fight.enemy_table)
	var units: Array[Combatant] = []
	for c in fight.combatants:
		var u := c.clone_for_preview()
		u.energy_spent_milli = c.energy_spent_milli
		units.append(u)
	copy.combatants = units
	copy.timeline = Timeline.new(units, fight.timeline.threshold)
	copy.timeline.current_tick = fight.timeline.current_tick
	copy.pending_actor = copy.combatant(fight.pending_actor.id) if fight.pending_actor != null else null
	copy.action_count = fight.action_count
	copy.action_tags = fight.action_tags.duplicate()
	copy.log_lines = PackedStringArray()
	return copy
