class_name BotSquadProvider
extends SquadProvider
## Supplies the fielded bots of a real BotSquad to the overworld, in place of
## StubSquadProvider.

var _squad: BotSquad


func _init(squad: BotSquad) -> void:
	_squad = squad


## Summaries of the fielded bots, in field order. Fresh copies every call.
func get_squad() -> Array[SquadMemberSummary]:
	var summaries: Array[SquadMemberSummary] = []
	if _squad == null:
		return summaries
	for bot in _squad.get_fielded():
		summaries.append(bot.to_summary())
	return summaries
