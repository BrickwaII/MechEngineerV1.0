class_name BotSquadStorage
extends RefCounted
## Saves a BotSquad to a Godot resource file and reads it back.
## Use a .tres path for text or .res for binary.


static func save_squad(squad: BotSquad, path: String) -> Error:
	if squad == null or not squad.is_valid():
		return ERR_INVALID_DATA
	return ResourceSaver.save(squad, path)


## The squad stored at `path`, or null if the file is missing, holds something
## else, or holds an invalid squad. Always reads the file, never a cached copy.
static func load_squad(path: String) -> BotSquad:
	if not ResourceLoader.exists(path):
		return null
	var squad := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as BotSquad
	if squad == null or not squad.is_valid():
		return null
	return squad
