class_name DraftPicker
extends RefCounted
## The rules of the squad draft, with no scene: the seeded draft from
## BotFactory, and which bots the player has picked. Picks are kept in a
## BotSquad, so the fielded bots reach the fight as contracts
## SquadMemberSummary data through BotSquadProvider.

var tuning: BotTuning
var draft_seed: int
## Drafted bots and the picks, in pick order.
var squad: BotSquad


func _init(p_tuning: BotTuning, p_draft_seed: int) -> void:
	tuning = p_tuning
	draft_seed = p_draft_seed
	var no_picks: Array[String] = []
	squad = BotSquad.new(BotFactory.new(tuning).build_draft(draft_seed), no_picks, tuning.squad_size)


func bots() -> Array[Bot]:
	return squad.bots


func squad_size() -> int:
	return squad.squad_size


func picked_ids() -> Array[String]:
	return squad.fielded_ids


func is_picked(bot_id: String) -> bool:
	return bot_id in squad.fielded_ids


## Picks the bot, or drops it if already picked. Returns "" or why not.
func toggle(bot_id: String) -> String:
	if squad.get_bot(bot_id) == null:
		return "no bot %s in the draft" % bot_id
	if is_picked(bot_id):
		squad.fielded_ids.erase(bot_id)
		return ""
	if squad.fielded_ids.size() >= squad.squad_size:
		return "the squad is full: drop a bot first"
	squad.fielded_ids.append(bot_id)
	return ""


## A full squad starts the fight.
func can_start() -> bool:
	return squad.fielded_ids.size() == squad.squad_size and squad.is_valid()


## The picked bots, in pick order, as the fight and the map see them.
func summaries() -> Array[SquadMemberSummary]:
	return BotSquadProvider.new(squad).get_squad()
