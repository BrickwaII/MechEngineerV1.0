class_name BotLibrary
extends RefCounted
## A folder of saved bots for the dev tools. Each bot is its own file: a
## BotSquad holding that one bot, fielded, written with BotSquadStorage, so any
## code that reads squads can read these files too.

const EXTENSION := "tres"


## A fresh bot with the low end of every stat range, the first starting skills
## of the catalog, and the tuning's augment slots. A starting point to edit.
static func new_bot(tuning: BotTuning, bot_id: String, bot_name: String) -> Bot:
	var stats := UnitStats.new()
	for stat in Bot.STAT_NAMES:
		stats.set(stat, tuning.stat_ranges[stat].x)
	var skills: Array[Skill] = []
	for template in tuning.skills.slice(0, tuning.starting_skill_count):
		var skill: Skill = template.duplicate()
		skill.level = tuning.starting_skill_level
		skills.append(skill)
	var slots: Array[AugmentSlot] = []
	for i in tuning.augment_slot_count:
		slots.append(AugmentSlot.new())
	return Bot.new(bot_id, bot_name, stats, Personality.new(tuning.starting_generation), skills, slots)


## Where the bot with `bot_id` is saved in `dir`.
static func path_for(dir: String, bot_id: String) -> String:
	return dir.path_join("%s.%s" % [bot_id.validate_filename(), EXTENSION])


## Saves `bot` as `dir`/<id>.tres. Returns OK, or an error when the bot is invalid
## or the file cannot be written.
static func save_bot(bot: Bot, dir: String, tuning: BotTuning) -> Error:
	if bot == null or not bot.is_valid():
		return ERR_INVALID_DATA
	var made := DirAccess.make_dir_recursive_absolute(dir)
	if made != OK:
		return made
	var bots: Array[Bot] = [bot]
	var fielded: Array[String] = [bot.id]
	var squad := BotSquad.new(bots, fielded, maxi(1, tuning.squad_size))
	return BotSquadStorage.save_squad(squad, path_for(dir, bot.id))


## The first fielded bot in the squad file at `path`, or null.
static func load_bot(path: String) -> Bot:
	var squad := BotSquadStorage.load_squad(path)
	if squad == null:
		return null
	var fielded := squad.get_fielded()
	return fielded[0] if not fielded.is_empty() else null


## The bot files in `dir`, sorted by path. Empty when the folder is missing.
static func list(dir: String) -> Array[String]:
	var out: Array[String] = []
	var access := DirAccess.open(dir)
	if access == null:
		return out
	for file in access.get_files():
		if file.get_extension() == EXTENSION:
			out.append(dir.path_join(file))
	out.sort()
	return out
