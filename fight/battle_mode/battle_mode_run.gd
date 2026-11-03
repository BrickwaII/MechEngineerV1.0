class_name BattleModeRun
extends RefCounted
## One Battle Mode run: fight after fight with no map, territory, countdown or
## resources. The squad keeps its growth (PostFight through FightAftermath:
## skill ranks, personality drift, banked uses) from one fight to the next.
## The same loop runs on screen (ui/battle_mode/) and headless
## (play_fight(), tools/battle_mode_sim.gd), so both report the same numbers.
##
##   var run := BattleModeRun.create(squad, "gauntlet", 7)
##   while not run.is_over():
##       var fight := run.begin_fight()      # the next encounter, ready to play
##       ... play it; call run.recorder.after_action(fight) after each action
##       var record := run.finish_fight(fight)
##   print(run.summary().format_text())
##
## Deterministic: the run seed sets every encounter and fight seed.
##
## HP between fights follows the hp-carryover switch (HpCarryover), as in a
## campaign; its default heals every bot to full, so each fight stands alone.
## TODO(decision: battle-mode-hp).

var squad: BotSquad
var ledger := SkillUseLedger.new()
var length: BattleModeTuning.Length
var run_seed := 0
var tuning: BattleModeTuning
var variants: FightVariants
var combat_tuning: CombatTuning
## The shipped enemies the encounters are drawn from.
var enemy_table: EnemyTable
## The squad's preset id, or "draft"; for the summary and the CSV.
var squad_label := "draft"
## Who plays the squad: a policy name, or "player"; for the summary.
var policy := "player"
## One per finished fight, in order.
var records: Array[BattleFightRecord] = []
## The PostFight report of the last finished fight, or null.
var last_report: PostFightReport
## The fight in progress and its recorder, or null between fights.
var fight: Fight
var recorder: BattleFightRecorder
var encounter: BattleEncounter
var _over := false
var _cleared := false


## A run of `length_id` for `p_squad` (its fielded bots fight). Nulls take the
## shipped tables and the player's switchboard choices.
static func create(p_squad: BotSquad, length_id: String, p_seed: int, p_variants: FightVariants = null,
		p_tuning: BattleModeTuning = null, p_combat_tuning: CombatTuning = null,
		p_enemy_table: EnemyTable = null) -> BattleModeRun:
	var run := BattleModeRun.new()
	run.squad = p_squad
	run.run_seed = p_seed
	run.tuning = p_tuning if p_tuning != null else BattleModeTuning.load_default()
	run.length = run.tuning.length(length_id)
	assert(run.length != null, "unknown Battle Mode length %s" % length_id)
	run.variants = p_variants if p_variants != null else FightVariants.load_active()
	run.combat_tuning = (p_combat_tuning if p_combat_tuning != null else CombatTuning.load_default()).with_variants(run.variants)
	run.enemy_table = p_enemy_table if p_enemy_table != null else EnemyTable.load_default()
	return run


## The squad of a preset in data/battle_mode/battle_mode.json, from its draft
## seed (the same bots the draft screen shows for that seed). Null if unknown.
static func preset_squad(preset_id: String, p_tuning: BattleModeTuning = null,
		bot_tuning: BotTuning = null) -> BotSquad:
	var t := p_tuning if p_tuning != null else BattleModeTuning.load_default()
	var preset := t.squad_preset(preset_id)
	if preset == null:
		return null
	var bt := bot_tuning if bot_tuning != null else BotTuning.load_default()
	var draft := BotFactory.new(bt).build_draft(preset.draft_seed)
	var bots: Array[Bot] = []
	var ids: Array[String] = []
	for i in preset.picks:
		if i >= 0 and i < draft.size() and bots.size() < bt.squad_size:
			bots.append(draft[i])
			ids.append(draft[i].id)
	return BotSquad.new(bots, ids, bt.squad_size)


## 1-based number of the next (or current) fight.
func fight_number() -> int:
	return records.size() + 1


func is_over() -> bool:
	return _over


## A gauntlet won to its last fight.
func is_cleared() -> bool:
	return _cleared


## The encounter of the next fight, drawn from the run seed.
func next_encounter() -> BattleEncounter:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("battle_mode:enemies:%d:%d" % [run_seed, fight_number()])
	return BattleEncounterPicker.pick(fight_number(), length, tuning, enemy_table, rng)


func fight_seed() -> int:
	return hash("battle_mode:fight:%d:%d" % [run_seed, fight_number()])


## The request of the next fight: the fielded bots, as they are now.
func next_request() -> FightRequest:
	var members: Array[SquadMemberSummary] = []
	for bot in squad.get_fielded():
		members.append(bot.to_summary())
	return FightRequest.new(FightRequest.Kind.ATTACK, "battle_mode", next_encounter().defense_level, members)


## The enemy table that fields the next encounter (for a screen that builds
## its own Fight).
func next_enemy_table() -> BattleEnemyTable:
	return BattleEnemyTable.for_encounter(enemy_table, next_encounter())


## Builds the next fight with its recorder attached; nothing has advanced yet.
func begin_fight() -> Fight:
	assert(not _over, "the run is over")
	return watch(Fight.new(next_request(), fight_seed(), combat_tuning, next_enemy_table()))


## Takes `p_fight` (built from next_request(), fight_seed() and
## next_enemy_table(), as a battle screen does) as the current fight and
## starts recording it. Call before its first advance().
func watch(p_fight: Fight) -> Fight:
	fight = p_fight
	encounter = (fight.enemy_table as BattleEnemyTable).encounter if fight.enemy_table is BattleEnemyTable else next_encounter()
	recorder = BattleFightRecorder.new(fight)
	return fight


## Ends the current fight: growth and HP (FightAftermath), its record, and
## whether the run goes on. Returns the record.
func finish_fight(p_fight: Fight = null) -> BattleFightRecord:
	var f := p_fight if p_fight != null else fight
	var rec := (recorder if f == fight and recorder != null else BattleFightRecorder.new(f)).finish(f, encounter)
	last_report = FightAftermath.apply(f, squad, ledger, variants)
	if last_report != null:
		for b in last_report.bots:
			rec.rank_ups += b.level_ups().size()
	records.append(rec)
	fight = null
	recorder = null
	encounter = null
	if not rec.victory:
		_over = true
	elif not length.is_endless() and records.size() >= length.fights:
		_over = true
		_cleared = true
	return rec


## Plays the next fight headless: `player_policy` plays the squad,
## `enemy_policy` (default IntentFightPolicy, as on screen) the enemies.
func play_fight(player_policy: FightPolicy, enemy_policy: FightPolicy = null) -> BattleFightRecord:
	var f := begin_fight()
	if enemy_policy == null:
		enemy_policy = IntentFightPolicy.new()
	var fallback := SimpleFightPolicy.new()
	var rng := HeadlessFightRunner.policy_rng(f.fight_seed)
	var actor := f.advance()
	while actor != null:
		HeadlessFightRunner.play_turn(
			f, actor, player_policy if actor.side == Combatant.Side.PLAYER else enemy_policy, fallback, rng)
		recorder.after_action(f)
		actor = f.advance()
	return finish_fight(f)


## Plays until the run ends or `max_fights` fights (0: no cap, which an
## endless run needs a losing squad for).
func play_to_end(player_policy: FightPolicy, enemy_policy: FightPolicy = null, max_fights := 0) -> BattleRunSummary:
	while not _over and (max_fights <= 0 or records.size() < max_fights):
		play_fight(player_policy, enemy_policy)
	return summary()


## Stops the run where it is (the player left).
func abandon() -> void:
	_over = true
	fight = null
	recorder = null


func run_id() -> String:
	return "%s-%s-%d" % [squad_label, length.id, run_seed]


func summary() -> BattleRunSummary:
	var s := BattleRunSummary.new()
	s.run_id = run_id()
	s.length_id = length.id
	s.run_seed = run_seed
	s.squad_label = squad_label
	s.policy = policy
	s.records = records.duplicate()
	s.cleared = _cleared
	s.dominant_share_percent = tuning.dominant_share_percent
	return s


## The name of a combat action id as the squad knows it: the name of the
## bot skill that fights with it ("Overcharge Shot" for heavy_strike), else
## the action's own name; "wait" is Wait.
func action_name(action_id: String) -> String:
	if action_id == "wait":
		return "Wait"
	var effect: String = _skill_effects().get(action_id, "")
	if not effect.is_empty() and squad != null:
		for bot in squad.get_fielded():
			for s in bot.skills:
				if s.effect_id == effect:
					return s.display_name
	var skill := combat_tuning.skill(action_id)
	return skill.display_name if skill != null else action_id


var _effects: Dictionary = {}


func _skill_effects() -> Dictionary:
	if _effects.is_empty():
		_effects = PostFightTuning.load_default().combat_skill_effects
	return _effects


## Appends this run's fights and its summary to fights.csv and runs.csv in
## `folder` (default the tuning's csv_folder, under user://). `run_id_override`
## replaces the run id (a played run adds the time, so replays do not merge).
func write_csv(folder := "", run_id_override := "") -> Error:
	var dir := folder if not folder.is_empty() else tuning.csv_folder
	var id := run_id_override if not run_id_override.is_empty() else run_id()
	var rows: Array = []
	for r in records:
		rows.append(r.csv_row(id))
	var err := CsvFile.append(dir.path_join("fights.csv"), BattleFightRecord.CSV_HEADER, rows)
	if err != OK:
		return err
	var s := summary()
	s.run_id = id
	return CsvFile.append(dir.path_join("runs.csv"), BattleRunSummary.CSV_HEADER, [s.csv_row()])
