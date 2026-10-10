class_name Combatant
extends RefCounted
## One unit in a fight: its stats, and the hp, energy and timeline state that
## change while the fight runs. Energy is kept in thousandths of a point
## (milli) so recharge stays in whole numbers.

enum Side { PLAYER, ENEMY }

## Thousandths per energy point. A unit conversion, not a tunable.
const MILLI := 1000
const NOT_WAITING := -1

var id: String
var display_name: String
var side: Side
## Position in the fight's roster; the last tie-break on the timeline.
var order: int
var stats: UnitStats
## The unit's skills in menu order. Read each one with skill(), which carries
## the unit's own name and level for it.
var skill_ids: Array[String] = []
## Skill id -> {"name": String, "level": int}: a bot's own name and level for
## a skill. Skills not listed use the tuning's name at level 1.
var skill_overrides: Dictionary = {}

var hp: int
var max_hp: int
## Timeline gauge. The unit is ready to act once it reaches the action threshold.
var gauge := 0
## Gauge gained per tick.
var charge_per_tick: int
var energy_milli: int
var max_energy_milli: int
## Normal recharge per tick.
var recharge_milli: int
## Recharge per tick while waiting.
var wait_recharge_milli: int
## Energy the unit is waiting to reach, or NOT_WAITING.
var wait_target_milli := NOT_WAITING
## Ticks spent in the current wait.
var wait_ticks := 0
var energy_spent_milli := 0
## Percent of the next hit this unit takes that is blocked. 0 when unguarded.
var guard_percent := 0

var _tuning: CombatTuning
## Skill id -> this unit's CombatSkill, built from the tuning and the overrides.
var _skills: Dictionary[String, CombatSkill] = {}


## p_side is a Side value; typed int because GDScript cannot type a
## constructor parameter with its own class's enum here.
func _init(
	p_id: String,
	p_display_name: String,
	p_side: int,
	p_order: int,
	p_stats: UnitStats,
	p_hp: int,
	p_skill_ids: Array[String],
	tuning: CombatTuning,
	p_skill_overrides: Dictionary = {},
) -> void:
	_tuning = tuning
	id = p_id
	display_name = p_display_name
	side = p_side
	order = p_order
	stats = p_stats
	max_hp = maxi(p_stats.hp, p_hp)
	hp = p_hp
	skill_ids = p_skill_ids.duplicate()
	skill_overrides = p_skill_overrides
	for skill_id in skill_ids:
		var base := tuning.skill(skill_id)
		if base == null:
			continue
		var o: Dictionary = skill_overrides.get(skill_id, {})
		_skills[skill_id] = base.at_level(
			int(o.get("level", 1)), String(o.get("name", "")), tuning.power_percent_per_level, tuning.max_guard_percent)
	charge_per_tick = maxi(tuning.min_charge_per_tick, p_stats.speed)
	max_energy_milli = maxi(0, p_stats.battery_capacity) * MILLI
	energy_milli = max_energy_milli * tuning.starting_energy_percent / 100
	recharge_milli = maxi(
		tuning.recharge_floor_milli_per_tick,
		maxi(0, p_stats.battery_capacity) * tuning.recharge_milli_per_battery_per_tick)
	wait_recharge_milli = recharge_milli * (100 + tuning.wait_recharge_bonus_percent) / 100


func is_alive() -> bool:
	return hp > 0


func is_waiting() -> bool:
	return wait_target_milli != NOT_WAITING


## Whole energy points, rounded down.
func energy() -> int:
	@warning_ignore("integer_division")
	return energy_milli / MILLI


func can_afford(skill: CombatSkill) -> bool:
	return energy_milli >= skill.energy_cost_milli()


func has_skill(skill_id: String) -> bool:
	return _skills.has(skill_id)


## This unit's version of `skill_id`: its own name, and power scaled by its
## level. Null when the unit does not have the skill.
func skill(skill_id: String) -> CombatSkill:
	return _skills.get(skill_id)


## This unit's skills in menu order.
func skills() -> Array[CombatSkill]:
	var out: Array[CombatSkill] = []
	for skill_id in skill_ids:
		if _skills.has(skill_id):
			out.append(_skills[skill_id])
	return out


func spend(skill: CombatSkill) -> void:
	energy_milli -= skill.energy_cost_milli()
	energy_spent_milli += skill.energy_cost_milli()


## True when the unit is ready to act at the current tick.
## TODO(decision: d-wait): a waiting unit snaps to the first tick it can afford
## the skill it waited for (at least one tick later). The alternative, picking
## an exact wait length, is open.
func is_ready(threshold: int) -> bool:
	if not is_alive():
		return false
	if is_waiting():
		return wait_ticks >= 1 and energy_milli >= wait_target_milli
	return gauge >= threshold


## One timeline tick: fill the gauge (unless holding in a wait) and recharge.
func tick() -> void:
	if not is_alive():
		return
	if is_waiting():
		wait_ticks += 1
		energy_milli = mini(max_energy_milli, energy_milli + wait_recharge_milli)
	else:
		gauge += charge_per_tick
		energy_milli = mini(max_energy_milli, energy_milli + recharge_milli)


func begin_wait(target_milli: int) -> void:
	wait_target_milli = target_milli
	wait_ticks = 0


## Called after the unit acts: spend one threshold of gauge, keep the overflow.
func finish_action(threshold: int) -> void:
	gauge = maxi(0, gauge - threshold)
	wait_target_milli = NOT_WAITING
	wait_ticks = 0


## A copy of the timing and guard state, for previews. Shares stats and skills.
func clone_for_preview() -> Combatant:
	var c := Combatant.new(id, display_name, side, order, stats, hp, skill_ids, _tuning, skill_overrides)
	c.max_hp = max_hp
	c.guard_percent = guard_percent
	c.gauge = gauge
	c.energy_milli = energy_milli
	c.wait_target_milli = wait_target_milli
	c.wait_ticks = wait_ticks
	return c
