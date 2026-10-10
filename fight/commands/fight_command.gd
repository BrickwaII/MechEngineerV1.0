class_name FightCommand
extends RefCounted
## One player input, as plain data: select a bot, select a skill, select a
## target, wait, or cancel. FightCommandHandler applies it to a Fight. Mouse,
## keyboard and tests all speak in these, so a fight plays the same whatever
## drives it.

enum Kind { SELECT_BOT, SELECT_SKILL, SELECT_TARGET, WAIT, CANCEL }

var kind: Kind
## Bot id for SELECT_BOT, skill id for SELECT_SKILL and WAIT, combatant id for
## SELECT_TARGET. Empty for CANCEL, and for a WAIT on the default skill.
var arg: String
## WAIT only: the exact ticks to wait, or 0 to wait until the skill is
## affordable. Above 0 needs the d-wait-length "exact" option.
var ticks := 0


func _init(p_kind := Kind.CANCEL, p_arg := "") -> void:
	kind = p_kind
	arg = p_arg


static func select_bot(bot_id: String) -> FightCommand:
	return FightCommand.new(Kind.SELECT_BOT, bot_id)


static func select_skill(skill_id: String) -> FightCommand:
	return FightCommand.new(Kind.SELECT_SKILL, skill_id)


static func select_target(target_id: String) -> FightCommand:
	return FightCommand.new(Kind.SELECT_TARGET, target_id)


## Wait for `skill_id`. When it is empty, wait for the handler's
## default_wait_skill(): the selected skill, else the cheapest one not yet
## affordable.
static func wait(skill_id := "", p_ticks := 0) -> FightCommand:
	var c := FightCommand.new(Kind.WAIT, skill_id)
	c.ticks = p_ticks
	return c


static func cancel() -> FightCommand:
	return FightCommand.new(Kind.CANCEL)


func _to_string() -> String:
	var kind_name: String = Kind.keys()[kind].to_lower()
	return kind_name if arg.is_empty() else "%s %s" % [kind_name, arg]
