class_name SquadProvider
extends RefCounted
## Supplies the squad the player has fielded. Extend it and override get_squad().
## StubSquadProvider is the stand-in until bot_data provides real bots.


## The fielded squad. Callers may change what they get back without affecting
## the provider.
func get_squad() -> Array[SquadMemberSummary]:
	push_error("%s does not override SquadProvider.get_squad()" % get_script().resource_path)
	return []
