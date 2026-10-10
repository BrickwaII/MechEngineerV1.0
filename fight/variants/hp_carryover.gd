class_name HpCarryover
extends RefCounted
## HP between fights, by the hp-carryover switch (FightVariants):
##   full_heal     every bot back to full (the default)
##   carry         a bot keeps the hp it ended the fight with; a downed bot
##                 comes back with downed_hp
##   partial_heal  end hp (downed_hp for a downed bot) plus heal_percent of
##                 max hp, capped at max
## A bot that did not fight starts from the hp it had.


## The hp a bot has after a fight it ended with `end_hp` of `max_hp`.
@warning_ignore("integer_division")
static func hp_after(end_hp: int, max_hp: int, variants: FightVariants) -> int:
	var key := FightVariants.HP_CARRYOVER
	match variants.option(key):
		FightVariants.HP_CARRY:
			return clampi(end_hp if end_hp > 0 else variants.param_int(key, "downed_hp", 1), 1, max_hp)
		FightVariants.HP_PARTIAL_HEAL:
			var start := end_hp if end_hp > 0 else variants.param_int(key, "downed_hp", 1)
			return clampi(start + max_hp * variants.param_int(key, "heal_percent") / 100, 1, max_hp)
	return max_hp


## Bot id -> the hp it ended `fight` with, for every squad member in it.
static func end_hp_by_id(fight: Fight) -> Dictionary[String, int]:
	var out: Dictionary[String, int] = {}
	if fight == null:
		return out
	for c in fight.combatants:
		if c.side == Combatant.Side.PLAYER:
			out[c.id] = c.hp
	return out
