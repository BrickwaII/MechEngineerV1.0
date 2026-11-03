class_name BattleDebugSession
extends RefCounted
## The battle debug simulator's engine (combat rework S9b), with no scene:
## everything the debugger panel does to a live fight goes through here, so
## it is tested headless. The panel (ui/dev/battle_debugger/) only shows it.
##
##   var dbg := BattleDebugSession.new(fight)
##   dbg.set_action_field("heavy_strike", "recovery", 60)   # live, at once
##   dbg.step()                                             # one decision
##   dbg.rewind_to(3)                                       # back to decision 3
##   var cmp := dbg.simulate()                              # S8 harness, as edited
##   print(dbg.preview_save().diff_text())                  # what Save writes
##   dbg.save_to_data()
##
## Edits are session-only: the session plays with its own copy of the
## fight's combat tuning (actions) and intent planner (AI weights,
## personalities), so nothing outside this fight sees them until Save to data
## writes them to their files (data/combat/actions.json,
## data/combat/intent/intent_weights.json), through the same loaders.
##
## Rewind: a snapshot (FightSnapshot) is kept at every decision point. Rewind
## puts the fight's state back exactly (units, timeline, log, forced
## intents, the policies' rng); definition edits (actions, AI weights,
## personalities) stay as they are now, so the same turn can be tried again
## with another value. Edits to fight state (hp, statuses, plating, gauge,
## the roster) are part of the snapshot at the decision they were made at.
## Restart builds the fight again from its request and seed, with the
## definitions as edited.
##
## Dev builds only: is_enabled().

## The feature tag that turns the debugger on in an exported build.
const FEATURE_TAG := "battle_debugger"

const FILE_ACTIONS := "actions"
const FILE_INTENT_WEIGHTS := "intent_weights"

## Action fields the inspector edits, in order: CombatSkill variable -> key
## in data/combat/actions.json.
const ACTION_FIELDS := {
	"display_name": "name",
	"energy_cost": "energy_cost",
	"recovery": "recovery",
	"power_percent": "power_percent",
	"hit_count": "hit_count",
	"damage_type": "damage_type",
	"applies_status": "applies_status",
	"payoff_condition": "payoff_condition",
	"payoff_bonus_percent": "payoff_bonus_percent",
	"effect": "effect",
	"target": "target",
}

## Unit fields the inspector edits, in order.
const UNIT_FIELDS: Array[String] = [
	"hp", "max_hp", "attack", "defense", "speed", "elasticity", "battery", "energy", "gauge",
	"plating", "max_plating", "guard_percent", "brace_absorb", "staggered",
]
## Unit fields that are one of the six stats: field -> UnitStats variable.
const STAT_FIELDS := {
	"attack": "attack", "defense": "defense", "speed": "speed", "elasticity": "elasticity",
	"battery": "battery_capacity",
}
## Personality fields the inspector edits.
const PERSONALITY_FIELDS: Array[String] = [
	"generation", "aggressive", "defensive", "solitary", "supportive", "reactive", "methodical",
]

## Emitted after anything changes the fight or the session.
signal changed

var fight: Fight
var settings: BattleDebugSettings
## The session's own combat tuning: action edits change it. The fight plays
## with it.
var tuning: CombatTuning
## The planner every enemy of this fight plans with (the fight's archetype
## intents, the enemy policy): AI weight and personality edits change it.
var planner: IntentPlanner
## Plays a squad bot when step() reaches its turn.
var player_policy: ForcedActionPolicy
var enemy_policy: ForcedActionPolicy
## Unit id -> the FightAction it plays next (force_action()).
var forced: Dictionary = {}
## Every tweak, in order.
var changes: Array[DebugChange] = []
## Data file key -> path Save to data writes; from the settings.
var data_paths: Dictionary = {}
## True when the latest rewind or restart replaced the unit objects (the
## roster had changed), so a screen showing them must rebuild its cards.
var roster_replaced := false
## The unit add_enemy() or copy_unit() made last.
var last_added_id := ""

## Fight.action_count -> the snapshot at that decision point.
var _snapshots: Dictionary = {}
var _rng: RandomNumberGenerator
var _fallback := SimpleFightPolicy.new()
## Copied unit id -> the id of the unit it was copied from (for the
## simulated request).
var _copied_from: Dictionary = {}


## True in dev builds: run from the editor, or exported with the
## battle_debugger feature tag. Release exports never have either.
static func is_enabled() -> bool:
	return OS.has_feature("editor") or OS.has_feature(FEATURE_TAG)


## Takes over `p_fight` for debugging. `p_planner` is the planner already
## planning its enemies (a battle screen's); it is given its own copies of
## its weights and personalities, so the session's edits reach every reader
## of it and nothing else. Policies default to the S8 harness's smart squad
## and IntentFightPolicy enemies.
func _init(p_fight: Fight, p_player_policy: FightPolicy = null, p_enemy_policy: FightPolicy = null,
		p_planner: IntentPlanner = null, p_settings: BattleDebugSettings = null) -> void:
	fight = p_fight
	settings = p_settings if p_settings != null else BattleDebugSettings.load_default()
	data_paths = settings.data_files.duplicate()
	if not data_paths.has(FILE_ACTIONS):
		data_paths[FILE_ACTIONS] = ActionTable.DEFAULT_PATH
	if not data_paths.has(FILE_INTENT_WEIGHTS):
		data_paths[FILE_INTENT_WEIGHTS] = IntentWeights.DEFAULT_PATH
	tuning = _own_tuning(fight.tuning)
	fight.tuning = tuning
	for c in fight.combatants:
		c.refresh_skills(tuning)
	planner = p_planner if p_planner != null else (
		fight.intent_planner if fight.intent_planner != null else IntentPlanner.new())
	planner.weights = planner.weights.copy()
	planner.personalities = _own_personalities(planner.personalities)
	fight.intent_planner = planner
	var problems: Array[String] = []
	player_policy = ForcedActionPolicy.new(
		p_player_policy if p_player_policy != null else FightScenario.make_policy("smart", problems), forced)
	enemy_policy = ForcedActionPolicy.new(
		p_enemy_policy if p_enemy_policy != null else IntentFightPolicy.new(planner), forced)
	_rng = HeadlessFightRunner.policy_rng(fight.fight_seed)
	fight.settle_outside_change()
	sync()


# --- Time -------------------------------------------------------------------

## Takes the snapshot of the decision the fight waits on (or its end) if it
## has none yet. Call after the fight moves on outside the session (a battle
## screen submitting the player's choice).
func sync() -> void:
	if (fight.is_awaiting_decision() or fight.is_over()) and not _snapshots.has(fight.action_count):
		_capture()


## Runs time to the next decision and snapshots it. Returns the unit to act,
## or null once the fight is over.
func advance() -> Combatant:
	var unit := fight.advance()
	sync()
	return unit


## Plays one decision with the policies (a forced action first) and runs
## time to the next. Returns false once the fight is over.
func step() -> bool:
	var actor := fight.advance()
	if actor == null:
		sync()
		return false
	var policy := player_policy if actor.side == Combatant.Side.PLAYER else enemy_policy
	HeadlessFightRunner.play_turn(fight, actor, policy, _fallback, _rng)
	_note_dropped(policy)
	fight.advance()
	sync()
	changed.emit()
	return not fight.is_over()


## Plays decisions until the fight ends or `max_steps` are played.
func run(max_steps := 1000) -> void:
	for i in max_steps:
		if not step():
			return


## Submits `action` for the unit the fight waits on, as a player would, and
## runs time to the next decision. Returns "" or why it was refused.
func submit(action: FightAction) -> String:
	fight.advance()
	var problem := fight.submit(action)
	if not problem.is_empty():
		return problem
	fight.advance()
	sync()
	changed.emit()
	return ""


## The decision points that can be rewound to (Fight.action_count values),
## oldest first.
func snapshot_points() -> Array[int]:
	var out: Array[int] = []
	for k: int in _snapshots:
		out.append(k)
	out.sort()
	return out


func snapshot(action_count: int) -> FightSnapshot:
	return _snapshots.get(action_count)


## Puts the fight back to decision point `action_count` (see the class
## comment). Later snapshots are dropped: playing on makes a new branch.
func rewind_to(action_count: int) -> String:
	if not _snapshots.has(action_count):
		return "no snapshot at decision %d" % action_count
	var from := fight.action_count
	_restore(_snapshots[action_count])
	for k: int in _snapshots.keys():
		if k > action_count:
			_snapshots.erase(k)
	for ch in changes:
		if _undone_by_rewind(ch) and ch.at_action > action_count:
			ch.undone = true
	_log(DebugChange.KIND_TIME, "fight", "rewind", from, action_count)
	changed.emit()
	return ""


## Rewinds one decision: to the decision point before the current one.
func rewind_one() -> String:
	var points := snapshot_points()
	var target := -1
	for p in points:
		if p < fight.action_count:
			target = p
	if target < 0:
		return "nothing to rewind to"
	return rewind_to(target)


## Builds the fight again from its request and seed (the same enemies),
## with the definitions as edited; fight-state edits and forced intents go.
func restart() -> String:
	var from := fight.action_count
	var fresh := Fight.new(fight.request, fight.fight_seed, tuning, fight.enemy_table)
	fresh.intent_planner = planner
	fresh.settle_outside_change()
	fresh.advance()
	var s := FightSnapshot.capture(fresh)
	forced.clear()
	_rng = HeadlessFightRunner.policy_rng(fight.fight_seed)
	s.extra = {"rng": _rng.state, "forced": {}}
	_restore(s)
	_snapshots.clear()
	_copied_from.clear()
	for ch in changes:
		if _undone_by_rewind(ch):
			ch.undone = true
	_capture()
	_log(DebugChange.KIND_TIME, "fight", "restart", from, 0)
	changed.emit()
	return ""


# --- Definitions ------------------------------------------------------------

## The action `action_id` as the session's tuning defines it, or null.
func action(action_id: String) -> CombatSkill:
	return tuning.skills.get(action_id)


## Every action id the tuning defines, in file order.
func action_ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in tuning.skills:
		out.append(id)
	return out


## Changes one field of action `action_id`'s definition (ACTION_FIELDS) for
## every unit holding it, at once. Returns "" or why it was refused (the
## definition would not validate).
func set_action_field(action_id: String, field: String, value: Variant) -> String:
	var def: CombatSkill = tuning.skills.get(action_id)
	if def == null:
		return "no action %s" % action_id
	if not ACTION_FIELDS.has(field):
		return "actions have no editable field %s" % field
	var edited := def.copy_definition()
	var before: Variant = edited.get(field)
	var v: Variant = _coerce(before, value)
	if typeof(v) == TYPE_NIL:
		return "%s needs a %s" % [field, type_string(typeof(before))]
	if _same_value(before, v):
		return ""
	edited.set(field, v)
	var problems := edited.validate(tuning.statuses.ids() if tuning.statuses != null else null)
	if not problems.is_empty():
		return problems[0]
	tuning.skills[action_id] = edited
	for c in fight.combatants:
		c.refresh_skills(tuning)
	var ch := _log(DebugChange.KIND_ACTION, action_id, field, before, v, FILE_ACTIONS,
		["actions", action_id, ACTION_FIELDS[field]])
	var blank := CombatSkill.from_dict(action_id, {})
	if field != "display_name":
		ch.has_default = true
		ch.default_value = blank.get(field)
	_after_edit()
	return ""


## AI weight `name`'s number `key` (IntentWeights.value_keys()).
func ai_weight(name: String, key: String) -> float:
	return planner.weights.value(name, key)


## Changes an intent weight (IntentWeights.NAMES; key "base" or a spectrum's
## lean) for every enemy's planning, at once.
func set_ai_weight(name: String, key: String, value: float) -> String:
	if not name in IntentWeights.NAMES:
		return "no AI weight %s" % name
	if not key in IntentWeights.value_keys():
		return "AI weights have no %s" % key
	var before := planner.weights.value(name, key)
	if is_equal_approx(before, value):
		return ""
	planner.weights.set_value(name, key, value)
	var ch := _log(DebugChange.KIND_AI, name, key, before, value, FILE_INTENT_WEIGHTS, ["weights", name, key])
	ch.has_default = true
	ch.default_value = 0.0
	_after_edit()
	return ""


## The personality unit `unit_id` is planned with.
func personality(unit_id: String) -> Personality:
	return planner.personalities.for_unit(unit_id)


## Changes one personality value (PERSONALITY_FIELDS) of one unit, for its
## planning. Session-only: enemy personalities are per enemy kind in data.
func set_personality(unit_id: String, field: String, value: float) -> String:
	if fight.combatant(unit_id) == null:
		return "no unit %s" % unit_id
	if not field in PERSONALITY_FIELDS:
		return "personalities have no %s" % field
	var p := planner.personalities.for_unit(unit_id).duplicate() as Personality
	var before: Variant = p.get(field)
	if field == "generation":
		p.generation = int(value)
	else:
		p.set(field, value)
	planner.personalities.by_unit[unit_id] = p
	_log(DebugChange.KIND_PERSONALITY, unit_id, field, before, p.get(field))
	_after_edit()
	return ""


# --- Fight state ------------------------------------------------------------

## Unit `unit_id`'s value for `field` (UNIT_FIELDS), or null.
func unit_field(unit_id: String, field: String) -> Variant:
	var c := fight.combatant(unit_id)
	if c == null:
		return null
	if STAT_FIELDS.has(field):
		return c.stats.get(STAT_FIELDS[field])
	if field == "energy":
		return c.energy()
	if field in UNIT_FIELDS:
		return c.get(field)
	return null


## Changes one field of unit `unit_id` (UNIT_FIELDS) mid-fight. Stats
## replace the unit's stats object (so snapshots keep the old one) and
## re-derive speed, battery and recharge. Returns "" or why not.
func set_unit_field(unit_id: String, field: String, value: Variant) -> String:
	var c := fight.combatant(unit_id)
	if c == null:
		return "no unit %s" % unit_id
	if not field in UNIT_FIELDS:
		return "units have no editable field %s" % field
	var before: Variant = unit_field(unit_id, field)
	var v: Variant = _coerce(before, value)
	if typeof(v) == TYPE_NIL:
		return "%s needs a %s" % [field, type_string(typeof(before))]
	match field:
		"hp":
			c.hp = clampi(v, 0, c.max_hp)
		"max_hp":
			c.max_hp = maxi(1, v)
			c.hp = mini(c.hp, c.max_hp)
		"energy":
			c.energy_milli = clampi(int(v) * Combatant.MILLI, 0, c.max_energy_milli)
		"gauge":
			c.gauge = v
		"plating":
			c.plating = maxi(0, v)
			c.max_plating = maxi(c.max_plating, c.plating)
		"max_plating":
			c.max_plating = maxi(0, v)
			c.plating = mini(c.plating, c.max_plating)
		"guard_percent":
			c.guard_percent = clampi(v, 0, 100)
		"brace_absorb":
			c.brace_absorb = maxi(0, v)
		"staggered":
			c.staggered = v
		_:
			var key: String = STAT_FIELDS[field]
			var amount := maxi(0, int(v))
			var delta := amount - int(c.stats.get(key))
			# A grown Scaler keeps its growth: its base stats move by the same amount.
			if c.base_stats != c.stats:
				c.base_stats = _with_stat(c.base_stats, key, int(c.base_stats.get(key)) + delta)
				c.set_stats(_with_stat(c.stats, key, amount))
			else:
				c.set_stats(_with_stat(c.stats, key, amount))
				c.base_stats = c.stats
			c.energy_milli = mini(c.energy_milli, c.max_energy_milli)
	_log(DebugChange.KIND_UNIT, unit_id, field, before, unit_field(unit_id, field))
	_after_edit()
	return ""


## Puts status `status_id` on the unit, or a stack more (StatusManager).
func apply_status(unit_id: String, status_id: String) -> String:
	var c := fight.combatant(unit_id)
	if c == null:
		return "no unit %s" % unit_id
	var before := c.status(status_id).stacks if c.has_status(status_id) else 0
	var held := fight.statuses.apply(c, status_id, "debug", fight.action_count)
	if held == null:
		return "cannot put %s on %s" % [status_id, unit_id]
	_log(DebugChange.KIND_STATUS, unit_id, status_id, before, held.stacks)
	_after_edit()
	return ""


func remove_status(unit_id: String, status_id: String) -> String:
	var c := fight.combatant(unit_id)
	if c == null:
		return "no unit %s" % unit_id
	var held := c.status(status_id)
	if held == null:
		return "%s does not hold %s" % [unit_id, status_id]
	c.statuses.erase(held)
	_log(DebugChange.KIND_STATUS, unit_id, status_id, held.stacks, 0)
	_after_edit()
	return ""


## Moves unit `unit_id` on the timeline: its gauge becomes `gauge` (a turn
## is Timeline.threshold; below 0 is a debt it fills first).
func set_gauge(unit_id: String, gauge: int) -> String:
	return set_unit_field(unit_id, "gauge", gauge)


## Gives unit `unit_id` the turn now: the fight waits on it instead. The unit
## that was waiting keeps its full gauge and acts next.
func give_turn(unit_id: String) -> String:
	var c := fight.combatant(unit_id)
	if c == null or not c.is_alive():
		return "no living unit %s" % unit_id
	if fight.is_over():
		return "the fight is over"
	fight.advance()
	var before := fight.pending_actor.id if fight.pending_actor != null else ""
	if before == unit_id:
		return ""
	c.cancel_wait()
	c.gauge = maxi(c.gauge, fight.timeline.threshold)
	fight.pending_actor = c
	_log(DebugChange.KIND_TIMELINE, unit_id, "turn", before, unit_id)
	_after_edit()
	return ""


## Unit `unit_id` plays `action` on its next turn, instead of what its policy
## or intent would choose (once; dropped if the fight refuses it then).
func force_action(unit_id: String, p_action: FightAction) -> String:
	var c := fight.combatant(unit_id)
	if c == null or not c.is_alive():
		return "no living unit %s" % unit_id
	if p_action == null or c.skill(p_action.skill_id) == null:
		return "%s has no such action" % unit_id
	var before: Variant = str(forced[unit_id]) if forced.has(unit_id) else null
	forced[unit_id] = p_action.copy()
	_log(DebugChange.KIND_INTENT, unit_id, "next", before, str(p_action))
	_after_edit()
	return ""


func clear_forced(unit_id: String) -> void:
	if not forced.has(unit_id):
		return
	var before := str(forced[unit_id])
	forced.erase(unit_id)
	_log(DebugChange.KIND_INTENT, unit_id, "next", before, null)
	_after_edit()


## The action unit `unit_id` is forced to play next, or null.
func forced_action(unit_id: String) -> FightAction:
	return forced.get(unit_id)


## Adds a fresh `enemy_id` (an enemy_tables.json id) to the enemy side, as
## the fight would field it. Its id is in last_added_id.
func add_enemy(enemy_id: String) -> String:
	var table := fight.enemy_table
	if not table.enemies.has(enemy_id):
		return "no enemy %s" % enemy_id
	var n := 1
	while fight.combatant("%s#%d" % [enemy_id, n]) != null:
		n += 1
	var id := "%s#%d" % [enemy_id, n]
	var stats := table.stats_for(enemy_id, fight.request, tuning)
	var shown := table.name_of(enemy_id) if n == 1 else "%s %d" % [table.name_of(enemy_id), n]
	var unit := Combatant.new(id, shown, Combatant.Side.ENEMY, _next_order(), stats, stats.hp,
		table.skills_of(enemy_id), tuning)
	var archetype := table.archetype_for(enemy_id)
	unit.archetype = archetype
	if archetype != null and archetype.is_plated():
		unit.plating = archetype.plating
		unit.max_plating = archetype.plating
		unit.plating_weakness = archetype.plating_weakness
	fight.combatants.append(unit)
	last_added_id = id
	_log(DebugChange.KIND_ROSTER, id, "add", null, enemy_id)
	_after_edit()
	return ""


## Adds a copy of unit `unit_id` (its state as it is now) to its side.
func copy_unit(unit_id: String) -> String:
	var src := fight.combatant(unit_id)
	if src == null:
		return "no unit %s" % unit_id
	var id := ""
	if src.side == Combatant.Side.ENEMY:
		var base := EnemyPersonalities.enemy_id_of(unit_id)
		var n := 1
		while fight.combatant("%s#%d" % [base, n]) != null:
			n += 1
		id = "%s#%d" % [base, n]
	else:
		var n := 2
		while fight.combatant("%s_%d" % [unit_id, n]) != null:
			n += 1
		id = "%s_%d" % [unit_id, n]
	var unit := FightSnapshot.clone_unit(src)
	unit.id = id
	unit.display_name = "%s (copy)" % src.display_name
	unit.order = _next_order()
	unit.refresh_skills(tuning)
	fight.combatants.append(unit)
	_copied_from[id] = _copied_from.get(unit_id, unit_id)
	last_added_id = id
	_log(DebugChange.KIND_ROSTER, id, "add", null, "copy of %s" % unit_id)
	_after_edit()
	return ""


## Takes unit `unit_id` out of the fight. If it was the one to act, time
## runs on to the next unit.
func remove_unit(unit_id: String) -> String:
	var c := fight.combatant(unit_id)
	if c == null:
		return "no unit %s" % unit_id
	fight.combatants.erase(c)
	forced.erase(unit_id)
	_log(DebugChange.KIND_ROSTER, unit_id, "remove", c.display_name, null)
	_after_edit()
	return ""


# --- Measure ----------------------------------------------------------------

## The set-up Simulate plays: the fight's request with each squad bot's
## stats as edited, the session's tuning and planner, and (unless the
## settings draw enemies) the fight's current enemies with their stats as
## edited. Fights start fresh: hp, energy and statuses mid-fight are not
## carried over.
func simulation_setup() -> ResolvedScenario:
	var r := ResolvedScenario.new()
	r.tuning = tuning
	var squad: Array[SquadMemberSummary] = []
	for c in fight.combatants:
		if c.side != Combatant.Side.PLAYER:
			continue
		var src := _member(String(_copied_from.get(c.id, c.id)))
		var stats := _with_stat(c.base_stats, "hp", c.max_hp)
		var skills: Array[Dictionary] = []
		var tag := ""
		if src != null:
			skills.assign(src.skills)
			tag = src.personality_tag
		squad.append(SquadMemberSummary.new(c.id, c.display_name, c.max_hp, c.max_hp, tag, stats, skills))
	if squad.is_empty():
		r.problems.append("the fight has no squad bots")
	var req := fight.request
	r.request = FightRequest.new(req.kind, req.territory_id, req.defense_level, squad)
	var personalities := _own_personalities(planner.personalities)
	if settings.draw_enemies:
		r.enemy_table = fight.enemy_table
	else:
		var lineup := []
		for c in fight.combatants:
			if c.side != Combatant.Side.ENEMY:
				continue
			var enemy_id := EnemyPersonalities.enemy_id_of(c.id)
			if not fight.enemy_table.enemies.has(enemy_id):
				r.problems.append("enemy %s is not in the enemy table" % c.id)
				continue
			lineup.append({"enemy_id": enemy_id, "stats": _with_stat(c.base_stats, "hp", c.max_hp)})
			# The copy keeps the unit's personality (and its edits).
			personalities.by_enemy["%s__%d" % [enemy_id, lineup.size()]] = planner.personalities.for_unit(c.id)
		if lineup.is_empty():
			r.problems.append("the fight has no enemies")
		r.enemy_table = DebugEnemyTable.of_lineup(fight.enemy_table, lineup)
	var sim_planner := IntentPlanner.new(planner.weights, personalities)
	r.intent_planner = sim_planner
	r.enemy_policy = IntentFightPolicy.new(sim_planner)
	r.player_policy = GreedyFightPolicy.new()
	return r


## Runs the S8 harness (PolicyComparison) on the set-up as edited: `runs`
## fights per policy on seeds from `base_seed` (defaults: the settings, and
## the fight's own seed). Read rows, checks, format_text().
func simulate(runs := -1, policies: Array[String] = [], base_seed := -1) -> PolicyComparison:
	var names: Array[String] = policies if not policies.is_empty() else settings.simulate_policies
	return PolicyComparison.compare(simulation_setup(), "debugger: %s seed %d" % [
		fight.request.territory_id, fight.fight_seed], names,
		runs if runs > 0 else settings.simulate_runs, base_seed if base_seed >= 0 else fight.fight_seed)


# --- Keep -------------------------------------------------------------------

## The data changes still to save: the latest of each key, unsaved, in log
## order. `seqs` limits them to those changes (empty: all).
func data_changes(seqs: Array[int] = []) -> Array[DebugChange]:
	var latest := {}
	for ch in changes:
		if ch.is_data():
			latest["%s:%s" % [ch.file, "/".join(PackedStringArray(ch.data_path))]] = ch
	var out: Array[DebugChange] = []
	for ch in changes:
		if not ch.is_data() or ch.saved:
			continue
		if latest["%s:%s" % [ch.file, "/".join(PackedStringArray(ch.data_path))]] != ch:
			continue
		if not seqs.is_empty() and not ch.seq in seqs:
			continue
		out.append(ch)
	return out


## What Save to data would write for `seqs` (empty: every unsaved data
## change): read its diff_text() before saving.
func preview_save(seqs: Array[int] = []) -> TuningPatch:
	return TuningPatch.build(data_changes(seqs), data_paths)


## Writes the chosen data changes (empty: all) to their files, then reloads
## each file through its loader and checks it. Returns the problems; empty
## when every change was written and reloads.
func save_to_data(seqs: Array[int] = []) -> Array[String]:
	var patch := preview_save(seqs)
	if not patch.problems.is_empty():
		return patch.problems
	var problems := patch.write()
	if not problems.is_empty():
		return problems
	for f in patch.files:
		problems.append_array(_reload_problems(String(f.file), String(f.path)))
	if not problems.is_empty():
		return problems
	var written := patch.seqs()
	for ch in changes:
		if ch.seq in written:
			ch.saved = true
	for ch in patch.unchanged:
		ch.saved = true
	changed.emit()
	return problems


## Writes every change (and the diff Save to data would write) to a JSON
## file for a later session: `path`, or a new file in the settings'
## export_dir. Returns the path written, or "" on an error.
func export_tuning_diff(path := "") -> String:
	if path.is_empty():
		DirAccess.make_dir_recursive_absolute(settings.export_dir)
		var stamp := Time.get_datetime_string_from_system(false, false).replace(":", "-").replace("T", "_")
		path = settings.export_dir.path_join("tuning_diff_%s.json" % stamp)
	var patch := preview_save()
	var data_out := []
	for ch in data_changes():
		data_out.append(ch.to_dict())
	var log_out := []
	for ch in changes:
		log_out.append(ch.to_dict())
	var diffs := {}
	for f in patch.files:
		diffs[String(f.path)] = String(f.diff)
	var doc := {
		"_comment": "Battle debugger tuning diff (S9b). data_changes are what Save to data would write; diffs show them against the files as they were; log is every tweak of the session.",
		"fight": {"seed": fight.fight_seed, "territory_id": fight.request.territory_id,
			"defense_level": fight.request.defense_level, "action_count": fight.action_count},
		"data_changes": data_out,
		"diffs": diffs,
		"problems": patch.problems,
		"log": log_out,
	}
	var err := JsonFile.write(path, doc, "\t", false)
	if err != OK:
		push_error("BattleDebugSession: cannot write %s (error %d)" % [path, err])
		return ""
	return path


## The change log as text, newest last.
func log_text() -> String:
	var lines := PackedStringArray()
	for ch in changes:
		lines.append(ch.text())
	return "\n".join(lines)


# --- Inside -----------------------------------------------------------------

func _capture() -> void:
	var s := FightSnapshot.capture(fight)
	s.extra = {"rng": _rng.state, "forced": _forced_copy()}
	_snapshots[fight.action_count] = s
	while _snapshots.size() > settings.max_snapshots:
		_snapshots.erase(snapshot_points()[0])


func _restore(s: FightSnapshot) -> void:
	roster_replaced = s.restore_into(fight)
	for c in fight.combatants:
		c.refresh_skills(tuning)
	_rng.state = int(s.extra.get("rng", _rng.state))
	forced.clear()
	var held: Dictionary = s.extra.get("forced", {})
	for id: String in held:
		forced[id] = (held[id] as FightAction).copy()
	fight.settle_outside_change()


## After an edit: the fight settles (a downed unit loses its turn, the end
## is checked, intents re-plan) and the decision point's snapshot is taken
## again, so a rewind to it keeps the edit.
func _after_edit() -> void:
	fight.settle_outside_change()
	if fight.pending_actor == null and not fight.is_over():
		fight.advance()
	_capture()
	changed.emit()


func _log(kind: String, subject: String, field: String, before: Variant, after: Variant,
		file := "", data_path: Array = []) -> DebugChange:
	var ch := DebugChange.new()
	ch.seq = changes.size() + 1
	ch.at_action = fight.action_count
	ch.kind = kind
	ch.subject = subject
	ch.field = field
	ch.before = before
	ch.after = after
	ch.file = file
	ch.data_path = data_path
	changes.append(ch)
	return ch


## Fight-state changes a rewind past them undoes; definition edits stay.
static func _undone_by_rewind(ch: DebugChange) -> bool:
	return not ch.is_data() and ch.kind != DebugChange.KIND_PERSONALITY and ch.kind != DebugChange.KIND_TIME


func _note_dropped(policy: ForcedActionPolicy) -> void:
	for id: String in policy.dropped:
		_log(DebugChange.KIND_INTENT, id, "dropped", policy.dropped[id], null)
	policy.dropped.clear()


func _forced_copy() -> Dictionary:
	var out := {}
	for id: String in forced:
		out[id] = (forced[id] as FightAction).copy()
	return out


func _member(member_id: String) -> SquadMemberSummary:
	for m in fight.request.squad:
		if m.id == member_id:
			return m
	return null


func _next_order() -> int:
	var top := -1
	for c in fight.combatants:
		top = maxi(top, c.order)
	return top + 1


func _reload_problems(file: String, path: String) -> Array[String]:
	var out: Array[String] = []
	match file:
		FILE_ACTIONS:
			var table := ActionTable.load_file(path)
			if table == null:
				out.append("%s does not reload" % path)
			else:
				out.append_array(table.validate(tuning.statuses))
		FILE_INTENT_WEIGHTS:
			var w := IntentWeights.load_file(path)
			if w == null:
				out.append("%s does not reload" % path)
			else:
				out.append_array(w.validate())
	return out


## A copy of `t` the session may change: its own action definitions.
static func _own_tuning(t: CombatTuning) -> CombatTuning:
	var own := t.with_variants(t.variants)
	var skills: Dictionary[String, CombatSkill] = {}
	for id: String in t.skills:
		skills[id] = t.skills[id].copy_definition()
	own.skills = skills
	return own


## A copy of `p` whose per-unit personalities the session may change; the
## per-enemy ones are shared (never changed in place).
static func _own_personalities(p: EnemyPersonalities) -> EnemyPersonalities:
	var own := EnemyPersonalities.new()
	for id: String in p.by_enemy:
		own.by_enemy[id] = p.by_enemy[id]
	for id: String in p.by_unit:
		own.by_unit[id] = p.by_unit[id]
	return own


static func _with_stat(s: UnitStats, key: String, value: int) -> UnitStats:
	var out := UnitStats.new(s.hp, s.attack, s.defense, s.speed, s.elasticity, s.battery_capacity)
	out.set(key, value)
	return out


## `value` as the type of `like` (an edit typed into a text box), or null
## when it cannot be.
static func _coerce(like: Variant, value: Variant) -> Variant:
	match typeof(like):
		TYPE_INT:
			if typeof(value) == TYPE_STRING:
				return int(value) if (value as String).strip_edges().is_valid_int() else null
			if typeof(value) in [TYPE_INT, TYPE_FLOAT, TYPE_BOOL]:
				return int(value)
			return null
		TYPE_FLOAT:
			if typeof(value) == TYPE_STRING:
				return float(value) if (value as String).strip_edges().is_valid_float() else null
			if typeof(value) in [TYPE_INT, TYPE_FLOAT]:
				return float(value)
			return null
		TYPE_BOOL:
			if typeof(value) == TYPE_STRING:
				return (value as String).strip_edges().to_lower() in ["true", "1", "yes", "on"]
			return bool(value)
		TYPE_STRING:
			return str(value).strip_edges()
	return value


static func _same_value(a: Variant, b: Variant) -> bool:
	return typeof(a) == typeof(b) and a == b
