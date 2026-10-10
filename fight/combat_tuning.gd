class_name CombatTuning
extends RefCounted
## Every tunable combat number, loaded from data/combat/combat_tuning.json.
## Tests may build one with from_dict() and change fields directly.

const DEFAULT_PATH := "res://data/combat/combat_tuning.json"

## Gauge a unit must fill before it acts.
var action_threshold: int
## Gauge gained per tick by a unit whose speed is lower than this.
var min_charge_per_tick: int
## Energy recharge per tick, in thousandths of a point, per battery point.
var recharge_milli_per_battery_per_tick: int
## Recharge per tick never drops below this, in thousandths of a point.
var recharge_floor_milli_per_tick: int
## Energy each unit starts a fight with, in percent of its pool.
var starting_energy_percent: int
## Extra recharge while waiting, in percent of normal recharge. 0 is a plain wait.
## TODO(decision: d-wait): the form of the wait bonus is open. Default until
## decided: waiting banks extra charge toward the unit's next action.
var wait_recharge_bonus_percent: int
## Share of the defender's defense subtracted from raw damage, in percent.
var defense_percent: int
## Damage never drops below this.
var min_damage: int
## A fight that reaches this many actions ends in defeat.
var max_actions: int
var grid_base_cost: float
var grid_cost_per_defense_level: float
var grid_cost_per_energy_spent: float
## Skill ids every squad member has, in menu order.
var player_skills: Array[String] = []
var skills: Dictionary[String, CombatSkill] = {}


static func load_default() -> CombatTuning:
	return load_file(DEFAULT_PATH)


static func load_file(path: String) -> CombatTuning:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("CombatTuning: cannot read %s" % path)
		return null
	return from_dict(parsed)


static func from_dict(d: Dictionary) -> CombatTuning:
	var t := CombatTuning.new()
	t.action_threshold = int(d.timeline.action_threshold)
	t.min_charge_per_tick = int(d.timeline.min_charge_per_tick)
	t.recharge_milli_per_battery_per_tick = int(d.energy.recharge_milli_per_battery_per_tick)
	t.recharge_floor_milli_per_tick = int(d.energy.recharge_floor_milli_per_tick)
	t.starting_energy_percent = int(d.energy.starting_percent)
	t.wait_recharge_bonus_percent = int(d.wait.recharge_bonus_percent)
	t.defense_percent = int(d.damage.defense_percent)
	t.min_damage = int(d.damage.min_damage)
	t.max_actions = int(d.fight.max_actions)
	t.grid_base_cost = float(d.grid.base_cost)
	t.grid_cost_per_defense_level = float(d.grid.cost_per_defense_level)
	t.grid_cost_per_energy_spent = float(d.grid.cost_per_energy_spent)
	for id: String in d.player_skills:
		t.player_skills.append(id)
	for id: String in d.skills:
		var s: Dictionary = d.skills[id]
		t.skills[id] = CombatSkill.new(id, s.name, int(s.energy_cost), int(s.power_percent))
	return t


## Problems that would make fights misbehave; empty when the tuning is usable.
func validate() -> Array[String]:
	var problems: Array[String] = []
	if action_threshold < 1:
		problems.append("action_threshold must be at least 1")
	if min_charge_per_tick < 1:
		problems.append("min_charge_per_tick must be at least 1")
	if recharge_floor_milli_per_tick < 1:
		problems.append("recharge_floor_milli_per_tick must be at least 1")
	if wait_recharge_bonus_percent < 0:
		problems.append("wait_recharge_bonus_percent may not be negative")
	if max_actions < 1:
		problems.append("max_actions must be at least 1")
	for id in player_skills:
		if not skills.has(id):
			problems.append("player skill %s is not defined" % id)
	return problems


func skill(id: String) -> CombatSkill:
	return skills.get(id)
