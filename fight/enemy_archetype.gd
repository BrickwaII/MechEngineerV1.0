class_name EnemyArchetype
extends RefCounted
## One enemy archetype: plating, a fixed intent pattern and per-action
## scaling. Plain data, read from data/combat/archetypes.json by
## EnemyArchetypeTable. The combat rework plan's EnemyArchetypeDef (S1).
##
## An enemy in data/combat/enemy_tables.json may name one ("archetype").
## Fights read plating and plating_weakness (S4: Fight, StaggerRules); S5
## gives the intent pattern and scaling meaning.
##
## Intent pattern: the steps the enemy repeats, one per turn, in order:
##   plan      the intent planner picks as it does today
##   wind_up   waits (free), telegraphing the next step (the Charger's big
##             hit): the hit and its target are committed the moment the wait
##             begins, and the wait cannot end before wind_up_opponent_actions
##             opponent decisions have resolved (the deep dive's fairness rule)
##   <action>  any action id (data/combat/actions.json): uses that action, or
##             waits for it while it cannot afford it
## An empty pattern is "plan" every turn. A Stagger cancels a committed hit
## and starts the pattern over (S5; ArchetypeRules).

const STEP_PLAN := "plan"
const STEP_WIND_UP := "wind_up"
const STEPS: Array[String] = [STEP_PLAN, STEP_WIND_UP]

## Stats per-action scaling may grow (UnitStats fields). Not hp: an hp gain
## mid-fight would need its own rule for current hp.
const SCALABLE_STATS: Array[String] = ["attack", "defense", "speed", "elasticity", "battery_capacity"]

var id: String
var display_name: String
## Plating pips at fight start; 0 is unplated. Each hit strips one, a hit of
## the plating_weakness damage type more (StaggerRules); at 0 the enemy is
## Staggered.
var plating := 0
## The damage type (CombatSkill.damage_type) that strips extra plating; ""
## for none.
var plating_weakness := ""
## Steps from STEPS or action ids, repeated in order. Empty: always plan.
var intent_pattern: Array[String] = []
## Stat name (SCALABLE_STATS) -> percent of the base stat gained each time the
## enemy acts (the Scaler). Empty: no scaling.
var scaling_percent_per_action: Dictionary[String, int] = {}
## Opponent decisions that must resolve between a wind_up and the hit it
## telegraphs: the wind-up wait cannot end sooner (at least 1 for a fair
## telegraph of a lethal hit; 0 lets it end as a plain wait would).
var wind_up_opponent_actions := 1


## The archetype defined by one entry of data/combat/archetypes.json. Keys
## left out take the defaults above.
static func from_dict(p_id: String, d: Dictionary) -> EnemyArchetype:
	var a := EnemyArchetype.new()
	a.id = p_id
	a.display_name = String(d.get("name", p_id))
	a.plating = int(d.get("plating", 0))
	a.plating_weakness = String(d.get("plating_weakness", ""))
	for step: Variant in d.get("intent_pattern", []):
		a.intent_pattern.append(String(step))
	var scaling: Dictionary = d.get("scaling_percent_per_action", {})
	for stat: Variant in scaling:
		a.scaling_percent_per_action[String(stat)] = int(scaling[stat])
	a.wind_up_opponent_actions = int(d.get("wind_up_opponent_actions", a.wind_up_opponent_actions))
	return a


func is_plated() -> bool:
	return plating > 0


func scales() -> bool:
	return not scaling_percent_per_action.is_empty()


## The pattern step for a unit at `index` (0-based, repeating); STEP_PLAN for
## an empty pattern.
func step_at(index: int) -> String:
	if intent_pattern.is_empty():
		return STEP_PLAN
	return intent_pattern[posmod(index, intent_pattern.size())]


## The action a wind_up at `index` telegraphs: the next step that names an
## action, or "" when a plan step (or another wind_up only) follows it.
func action_after(index: int) -> String:
	for i in range(1, intent_pattern.size() + 1):
		var step := step_at(index + i)
		if step == STEP_WIND_UP:
			continue
		return "" if step == STEP_PLAN else step
	return ""


## Problems with this definition; empty when usable. `action_ids` are the
## actions a pattern may name; null skips that check.
func validate(action_ids: Variant = null) -> Array[String]:
	var problems: Array[String] = []
	if id.is_empty():
		problems.append("an archetype has no id")
	if display_name.is_empty():
		problems.append("archetype %s has no name" % id)
	if plating < 0:
		problems.append("archetype %s plating may not be negative" % id)
	if not plating_weakness.is_empty() and plating <= 0:
		problems.append("archetype %s has a plating_weakness but no plating" % id)
	for step in intent_pattern:
		if step in STEPS:
			continue
		if action_ids == null:
			continue
		if not step in action_ids:
			problems.append("archetype %s intent step '%s' is neither %s nor an action" % [
				id, step, " nor ".join(STEPS)])
	if not intent_pattern.is_empty() and intent_pattern.all(func(s: String) -> bool: return s == STEP_WIND_UP):
		problems.append("archetype %s only winds up and never acts" % id)
	if wind_up_opponent_actions < 0:
		problems.append("archetype %s wind_up_opponent_actions may not be negative" % id)
	for stat in scaling_percent_per_action:
		if not stat in SCALABLE_STATS:
			problems.append("archetype %s scales unknown stat '%s'" % [id, stat])
		if scaling_percent_per_action[stat] == 0:
			problems.append("archetype %s scales %s by 0" % [id, stat])
	return problems
