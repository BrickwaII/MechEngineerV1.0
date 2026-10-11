class_name RunSave
extends Resource
## A saved run: the map's RunState, the bots and their banked skill uses, and
## the run's seed. One Godot resource file. Use .res (binary): a .tres text file
## rounds some floats in their last digit, so a reload would not be exact.

## 2: two-ended personalities and named skill ranks (GrowthSaveUpgrade
## converts a version 1 file as it loads).
const FORMAT_VERSION := GrowthSaveUpgrade.FORMAT_GROWTH

## Defaults to version 1: Godot leaves a property at its default out of the
## file, and version 1 files hold none, so a file without one is version 1.
## make() stamps FORMAT_VERSION, which is then always written.
@export var version := GrowthSaveUpgrade.FORMAT_FLAT_LEVELS
@export var run_seed := 0
@export var squad: BotSquad
@export var ledger: SkillUseLedger
## RunState.to_dict() of the map.
@export var map_state: Dictionary = {}


static func make(p_run_seed: int, p_squad: BotSquad, p_ledger: SkillUseLedger, state: RunState) -> RunSave:
	var save := RunSave.new()
	save.version = FORMAT_VERSION
	save.run_seed = p_run_seed
	save.squad = p_squad
	save.ledger = p_ledger
	save.map_state = state.to_dict()
	return save


## The map state, or null if it does not read back.
func run_state() -> RunState:
	return RunState.from_dict(map_state)


func is_valid() -> bool:
	return (version == FORMAT_VERSION and squad != null and squad.is_valid()
		and ledger != null and run_state() != null)


func save_file(path: String) -> Error:
	if not is_valid():
		return ERR_INVALID_DATA
	return ResourceSaver.save(self, path)


## The run stored at `path`, or null if the file is missing, holds something
## else, or holds a broken run. Always reads the file, never a cached copy.
static func load_file(path: String) -> RunSave:
	if not ResourceLoader.exists(path):
		return null
	var save := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as RunSave
	if save != null and save.version < FORMAT_VERSION:
		GrowthSaveUpgrade.upgrade_squad(save.squad, save.version)
		save.version = FORMAT_VERSION
	if save == null or not save.is_valid():
		return null
	return save
