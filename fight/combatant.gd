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
## Below 0 after a long recovery or a delay: a debt the unit fills first.
var gauge := 0
## Gauge a delay took from the unit while it waited (a wait holds a full
## gauge, so the delay cannot land yet); paid when it next finishes an action.
## See TimelineOps.
var held_delay := 0
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
## Exact length of the current wait in ticks, or 0 for a wait that ends on the
## first tick the unit can afford its skill. See WaitRules (d-wait-length).
var wait_length := 0
var energy_spent_milli := 0
## Percent of the next hit this unit takes that is blocked. 0 when unguarded.
var guard_percent := 0
## Share of the damage the guard blocks that goes back to the attacker (a
## Mega or Ultra guard skill's reflect). Cleared with the guard.
var reflect_percent := 0
## Statuses the unit holds (Exposed, ...), in the order first applied. Changed
## only through StatusManager. See StatusInstance.
var statuses: Array[StatusInstance] = []
## Damage still to absorb from a Brace (DamageRules.brace_absorb), across
## every hit, until this unit's next action. 0 when not bracing.
var brace_absorb := 0
## Plating pips left (an enemy archetype's plating; StaggerRules). 0: unplated
## or broken.
var plating := 0
## Plating at fight start; what recovering from a Stagger restores toward.
var max_plating := 0
## The damage type that strips extra plating; "" for none.
var plating_weakness := ""
## True from the hit that breaks the plating until the unit's next turn, which
## it spends recovering. Hits on it deal StaggerRules.damage_bonus_percent more.
## Intent planners read it: a Staggered unit has no intent.
var staggered := false
## The enemy archetype the unit was built from (Charger, Plated, Scaler), or
## null. Its intent pattern, wind-up and growth rules: ArchetypeRules.
var archetype: EnemyArchetype
## Index of the archetype's intent_pattern step the unit takes next.
var pattern_step := 0
## Archetype units only: the intent the fight last announced for the unit
## (FightEvent INTENT_CHANGED), or null for none. Never changed in place.
var intent: UnitIntent
## The hit a wind-up telegraphed (an ATTACK intent), kept until the unit
## lands it or is Staggered; only its target may change, when the target goes
## down. Null when the unit is committed to nothing.
var committed: UnitIntent
## Opponent decisions still to resolve before this unit's wind-up wait may
## end (EnemyArchetype.wind_up_opponent_actions). 0 when not winding up.
var telegraph_wait := 0
## The unit's stats before archetype growth (the Scaler); `stats` is replaced,
## never changed in place, as it grows, so preview copies sharing the old
## stats are untouched.
var base_stats: UnitStats
## Times the unit has grown (EnemyArchetype.scaling_percent_per_action).
var growth := 0

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
	base_stats = p_stats
	max_hp = maxi(p_stats.hp, p_hp)
	hp = p_hp
	skill_ids = p_skill_ids.duplicate()
	skill_overrides = p_skill_overrides
	for skill_id in skill_ids:
		if tuning.skill(skill_id) == null:
			continue
		var o: Dictionary = skill_overrides.get(skill_id, {})
		_skills[skill_id] = tuning.skill_at(skill_id, int(o.get("level", 1)), String(o.get("name", "")))
	_derive_from_stats()
	energy_milli = max_energy_milli * tuning.starting_energy_percent / 100


## Rebuilds the unit's skills from `tuning` (its own names and levels kept):
## for dev tools that change an action's definition mid-fight (the battle
## debugger, S9b). Fights never call it.
func refresh_skills(tuning: CombatTuning) -> void:
	_tuning = tuning
	var fresh: Dictionary[String, CombatSkill] = {}
	for skill_id in skill_ids:
		if tuning.skill(skill_id) == null:
			continue
		var o: Dictionary = skill_overrides.get(skill_id, {})
		fresh[skill_id] = tuning.skill_at(skill_id, int(o.get("level", 1)), String(o.get("name", "")))
	_skills = fresh


## Replaces the unit's stats (archetype growth) and what is worked out from
## them: charge, battery and recharge. Hp and energy held stay as they are.
func set_stats(p_stats: UnitStats) -> void:
	stats = p_stats
	_derive_from_stats()


func _derive_from_stats() -> void:
	charge_per_tick = SpeedRules.charge_per_tick(stats.speed, _tuning)
	max_energy_milli = maxi(0, stats.battery_capacity) * MILLI
	recharge_milli = maxi(
		EnergyRules.recharge_floor_milli(_tuning),
		maxi(0, stats.battery_capacity) * EnergyRules.recharge_milli_per_battery(_tuning))
	wait_recharge_milli = WaitRules.wait_recharge_milli(recharge_milli, _tuning)


func is_alive() -> bool:
	return hp > 0


func is_waiting() -> bool:
	return wait_target_milli != NOT_WAITING


## Whole energy points, rounded down.
func energy() -> int:
	@warning_ignore("integer_division")
	return energy_milli / MILLI


## The unit's instance of status `status_id`, or null when it does not hold it.
func status(status_id: String) -> StatusInstance:
	for s in statuses:
		if s.status_id == status_id:
			return s
	return null


func has_status(status_id: String) -> bool:
	return status(status_id) != null


## Ids of the statuses the unit holds, in order.
func status_ids() -> Array[String]:
	var out: Array[String] = []
	for s in statuses:
		out.append(s.status_id)
	return out


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
## TODO(decision: d-wait-length): by default a waiting unit snaps to the first
## tick it can afford the skill it waited for (at least one tick later). With
## the "exact" option a wait may instead last `wait_length` ticks.
func is_ready(threshold: int) -> bool:
	if not is_alive():
		return false
	if is_waiting():
		# A wind-up holds until its telegraph has been answered.
		if telegraph_wait > 0:
			return false
		if wait_length > 0:
			return wait_ticks >= wait_length
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


## Starts a wait for `target_milli` energy, or for exactly `length` ticks when
## it is above 0.
func begin_wait(target_milli: int, length := 0) -> void:
	wait_target_milli = target_milli
	wait_ticks = 0
	wait_length = maxi(0, length)


## Ends a wait without acting (a Stagger cancels a wind-up). The gauge stays.
func cancel_wait() -> void:
	wait_target_milli = NOT_WAITING
	wait_ticks = 0
	wait_length = 0
	telegraph_wait = 0


## Called after the unit acts: spend one threshold of gauge, keep the overflow,
## then pay any delay held during a wait. The action's recovery is added by
## TimelineOps.recover() after this.
func finish_action(threshold: int) -> void:
	gauge = maxi(0, gauge - threshold) - held_delay
	held_delay = 0
	wait_target_milli = NOT_WAITING
	wait_ticks = 0
	wait_length = 0
	telegraph_wait = 0


## A copy of the timing, guard, status, plating and archetype state, for
## previews. Shares stats (replaced, never changed in place), skills and the
## archetype.
func clone_for_preview() -> Combatant:
	var no_skills: Array[String] = []
	var c := Combatant.new(id, display_name, side, order, stats, hp, no_skills, _tuning, skill_overrides)
	c.skill_ids = skill_ids.duplicate()
	c._skills = _skills
	c.max_hp = max_hp
	c.guard_percent = guard_percent
	c.reflect_percent = reflect_percent
	for st in statuses:
		c.statuses.append(st.copy())
	c.brace_absorb = brace_absorb
	c.plating = plating
	c.max_plating = max_plating
	c.plating_weakness = plating_weakness
	c.staggered = staggered
	c.archetype = archetype
	c.pattern_step = pattern_step
	c.intent = intent
	c.committed = committed
	c.telegraph_wait = telegraph_wait
	c.base_stats = base_stats
	c.growth = growth
	c.gauge = gauge
	c.held_delay = held_delay
	c.energy_milli = energy_milli
	c.wait_target_milli = wait_target_milli
	c.wait_ticks = wait_ticks
	c.wait_length = wait_length
	return c
