class_name BotSquad
extends Resource
## The drafted bots and which of them are fielded. State and validation only.
## This is what a save file holds.

## Every drafted bot, in draft order.
@export var bots: Array[Bot] = []
## Ids of the fielded bots, in field order. Each must be in `bots`.
@export var fielded_ids: Array[String] = []
## How many bots may be fielded at once. Set from data/ by BotFactory.
@export var squad_size: int


func _init(p_bots: Array[Bot] = [], p_fielded_ids: Array[String] = [], p_squad_size := 0) -> void:
	bots = p_bots.duplicate()
	fielded_ids = p_fielded_ids.duplicate()
	squad_size = p_squad_size


## The bot with this id, or null.
func get_bot(bot_id: String) -> Bot:
	for bot in bots:
		if bot != null and bot.id == bot_id:
			return bot
	return null


## The fielded bots, in field order. Ids not in the squad are skipped.
func get_fielded() -> Array[Bot]:
	var fielded: Array[Bot] = []
	for bot_id in fielded_ids:
		var bot := get_bot(bot_id)
		if bot != null:
			fielded.append(bot)
	return fielded


## A squad of only the fielded bots, in field order, with no bench: a run
## keeps only the bots picked in the draft. The bots are shared, not copied.
func to_fielded_squad() -> BotSquad:
	return BotSquad.new(get_fielded(), fielded_ids, squad_size)


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	var ids := {}
	for bot in bots:
		if bot == null:
			errors.append("squad has an empty bot entry")
			continue
		errors.append_array(bot.validation_errors())
		if ids.has(bot.id):
			errors.append("squad holds bot id '%s' twice" % bot.id)
		ids[bot.id] = true
	if squad_size <= 0:
		errors.append("squad size %d must be above 0" % squad_size)
	if fielded_ids.size() > squad_size:
		errors.append("%d bots fielded, more than squad size %d" % [fielded_ids.size(), squad_size])
	var seen := {}
	for bot_id in fielded_ids:
		if not ids.has(bot_id):
			errors.append("fielded bot '%s' is not in the squad" % bot_id)
		if seen.has(bot_id):
			errors.append("bot '%s' is fielded twice" % bot_id)
		seen[bot_id] = true
	return errors


func is_valid() -> bool:
	return validation_errors().is_empty()
