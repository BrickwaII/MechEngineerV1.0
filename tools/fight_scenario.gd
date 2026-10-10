class_name FightScenario
extends RefCounted
## A fight set up for testing and balance: a squad, the enemies, and the
## policies that play both sides. Stored as JSON; see data/scenarios/README.md.
##
## Squad entries, any mix:
##   {"squad_file": "user://dev/bots/bolt.tres"}           fielded bots of a saved squad
##   {"squad_file": "...", "bot_id": "bot_2"}               one bot of a saved squad
##   {"draft_seed": 2024}                                   fielded bots of a seeded draft
##   {"bot": {"id": ..., "stats": {...}, ...}}             an inline bot (BotJson)
## Enemies: leave "enemies" out to draw them from the enemy table for
## "defense_level" with each fight's seed, or list them explicitly:
##   "rust_hound"  or  {"enemy": "rust_hound", "count": 2}  from the enemy table
##   {"squad_file": ...} / {"bot": {...}}                   a saved or inline bot as an enemy

const POLICIES := ["simple", "random", "intent"]
const KINDS := ["attack", "defend"]

var scenario_name := ""
var kind := FightRequest.Kind.ATTACK
var territory_id := "scenario"
var defense_level := 0
var squad_entries: Array = []
## Empty means: draw from the enemy table.
var enemy_entries: Array = []
var player_policy := "simple"
var enemy_policy := "simple"


static func from_dict(d: Dictionary) -> FightScenario:
	var s := FightScenario.new()
	s.scenario_name = str(d.get("name", ""))
	s.kind = maxi(0, KINDS.find(str(d.get("kind", "attack")))) as FightRequest.Kind
	s.territory_id = str(d.get("territory_id", "scenario"))
	s.defense_level = int(d.get("defense_level", 0))
	s.squad_entries = (d.get("squad", []) as Array).duplicate(true)
	s.enemy_entries = (d.get("enemies", []) as Array).duplicate(true)
	s.player_policy = str(d.get("player_policy", "simple"))
	s.enemy_policy = str(d.get("enemy_policy", "simple"))
	return s


func to_dict() -> Dictionary:
	var d := {
		"name": scenario_name,
		"kind": KINDS[kind],
		"territory_id": territory_id,
		"defense_level": defense_level,
		"squad": squad_entries.duplicate(true),
		"player_policy": player_policy,
		"enemy_policy": enemy_policy,
	}
	if not enemy_entries.is_empty():
		d["enemies"] = enemy_entries.duplicate(true)
	return d


## Everything needed to play this scenario: a request, an enemy table and the
## two policies. `problems` lists why it cannot be played; empty means it can.
func resolve(
	bot_tuning: BotTuning = null, base_table: EnemyTable = null, combat_tuning: CombatTuning = null,
) -> ResolvedScenario:
	bot_tuning = bot_tuning if bot_tuning != null else BotTuning.load_default()
	base_table = base_table if base_table != null else EnemyTable.load_default()
	combat_tuning = combat_tuning if combat_tuning != null else CombatTuning.load_default()
	var r := ResolvedScenario.new()
	r.tuning = combat_tuning
	if scenario_name.is_empty():
		r.problems.append("scenario has no name")
	if defense_level < FightRequest.MIN_DEFENSE_LEVEL or defense_level > FightRequest.MAX_DEFENSE_LEVEL:
		r.problems.append("defense level %d is outside %d to %d" % [
			defense_level, FightRequest.MIN_DEFENSE_LEVEL, FightRequest.MAX_DEFENSE_LEVEL])
	var squad: Array[SquadMemberSummary] = []
	for entry: Variant in squad_entries:
		for bot in _bots_of(entry, bot_tuning, r.problems):
			squad.append(bot.to_summary())
	if squad.is_empty():
		r.problems.append("scenario fields no squad")
	_check_unique_ids(squad, r.problems)
	r.request = FightRequest.new(kind, territory_id, defense_level, squad)
	r.enemy_table = _enemy_table(base_table, bot_tuning, combat_tuning, r.problems)
	r.player_policy = make_policy(player_policy, r.problems)
	r.enemy_policy = make_policy(enemy_policy, r.problems)
	return r


static func make_policy(policy_name: String, problems: Array[String]) -> FightPolicy:
	match policy_name:
		"simple":
			return SimpleFightPolicy.new()
		"random":
			return RandomFightPolicy.new()
		"intent":
			return IntentFightPolicy.new()
	problems.append("unknown policy '%s' (use %s)" % [policy_name, ", ".join(POLICIES)])
	return SimpleFightPolicy.new()


func _enemy_table(base: EnemyTable, bot_tuning: BotTuning, combat_tuning: CombatTuning, problems: Array[String]) -> EnemyTable:
	if enemy_entries.is_empty():
		return base
	var ids: Array[String] = []
	var extra := {}
	for entry: Variant in enemy_entries:
		var enemy_id := ""
		var count := 1
		if entry is String:
			enemy_id = entry
		elif entry is Dictionary and entry.has("enemy"):
			enemy_id = str(entry.enemy)
			count = int(entry.get("count", 1))
		if not enemy_id.is_empty():
			if not base.enemies.has(enemy_id):
				problems.append("unknown enemy '%s'" % enemy_id)
				continue
			for i in count:
				ids.append(enemy_id)
			continue
		for bot in _bots_of(entry, bot_tuning, problems):
			var custom_id := "custom_%s" % bot.id
			extra[custom_id] = _enemy_def(bot, combat_tuning)
			ids.append(custom_id)
	if ids.is_empty():
		problems.append("scenario lists enemies but none could be read")
	return FixedEnemyTable.from_table(base, ids, extra)


## A bot as an enemy definition. Bots' own skills do not drive fights yet:
## fight/ gives every squad member CombatTuning.player_skills, so a bot fielded
## as an enemy gets the same list.
static func _enemy_def(bot: Bot, combat_tuning: CombatTuning) -> Dictionary:
	var d := {"name": bot.display_name, "skills": combat_tuning.player_skills.duplicate()}
	for stat in Bot.STAT_NAMES:
		d[stat] = int(bot.stats.get(stat))
	return d


static func _bots_of(entry: Variant, bot_tuning: BotTuning, problems: Array[String]) -> Array[Bot]:
	var out: Array[Bot] = []
	if not entry is Dictionary:
		problems.append("cannot read entry %s" % [entry])
		return out
	if entry.has("bot"):
		var bot := BotJson.from_dict(entry.bot, bot_tuning, problems)
		if bot != null:
			out.append(bot)
	elif entry.has("squad_file"):
		var squad := BotSquadStorage.load_squad(str(entry.squad_file))
		if squad == null:
			problems.append("cannot load squad file %s" % entry.squad_file)
		elif entry.has("bot_id"):
			var bot := squad.get_bot(str(entry.bot_id))
			if bot == null:
				problems.append("%s has no bot '%s'" % [entry.squad_file, entry.bot_id])
			else:
				out.append(bot)
		else:
			out.append_array(squad.get_fielded())
	elif entry.has("draft_seed"):
		out.append_array(BotFactory.new(bot_tuning).build_squad(int(entry.draft_seed)).get_fielded())
	else:
		problems.append("cannot read entry %s" % [entry])
	return out


static func _check_unique_ids(squad: Array[SquadMemberSummary], problems: Array[String]) -> void:
	var seen := {}
	for member in squad:
		if seen.has(member.id):
			problems.append("squad holds bot id '%s' twice" % member.id)
		seen[member.id] = true
