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
## Used by the d-wait "banked" option; see WaitRules.
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
## Skill ids a squad member whose summary lists no skills has, in menu order.
var player_skills: Array[String] = []
## The skill every squad member keeps so it is never stuck: added when none of
## its own skills is a free single-target attack. "" adds none.
var basic_attack: String
## Bot skill effect_id (data/bot_data/skills.json) -> combat skill id.
var bot_skill_effects: Dictionary[String, String] = {}
## Power added per skill level above 1, in percent of the skill's power.
var power_percent_per_level: int
## The most of one hit a guard may block, in percent.
var max_guard_percent: int
var skills: Dictionary[String, CombatSkill] = {}
## Named ranks (data/combat/skill_ranks.json), used when the skill-progression
## switch is "ranks".
var skill_ranks: SkillRanks
## The fight-side switches of the variant switchboard. from_dict() gives the
## data file's defaults; the game sets the player's choices before a fight.
var variants: FightVariants


## The shipped file; read from disk once, a fresh object every call.
static func load_default() -> CombatTuning:
	var d: Variant = JsonFile.read_object_cached(DEFAULT_PATH)
	return from_dict(d) if d != null else load_file(DEFAULT_PATH)


static func load_file(path: String) -> CombatTuning:
	var d: Variant = JsonFile.read_object(path)
	if d == null:
		push_error("CombatTuning: cannot read %s" % path)
		return null
	return from_dict(d)


static func from_dict(d: Dictionary) -> CombatTuning:
	var t := CombatTuning.new()
	t.variants = FightVariants.defaults()
	t.skill_ranks = SkillRanks.load_default()
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
	# The bot-skill sections are optional; leaving one out turns its rule off.
	t.basic_attack = String(d.get("basic_attack", ""))
	var effects: Dictionary = d.get("bot_skill_effects", {})
	for effect_id: String in effects:
		if not effect_id.begins_with("_"):
			t.bot_skill_effects[effect_id] = String(effects[effect_id])
	t.power_percent_per_level = int(d.get("skill_levels", {}).get("power_percent_per_level", 0))
	t.max_guard_percent = int(d.get("guard", {}).get("max_percent", 100))
	for id: String in d.skills:
		var s: Dictionary = d.skills[id]
		t.skills[id] = CombatSkill.new(
			id, s.name, int(s.energy_cost), int(s.power_percent), String(s.get("effect", CombatSkill.EFFECT_DAMAGE)),
			String(s.get("target", "")))
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
	if basic_attack.is_empty():
		pass
	elif not skills.has(basic_attack):
		problems.append("basic attack %s is not defined" % basic_attack)
	elif not is_basic_attack(skills[basic_attack]):
		problems.append("basic attack %s must be a free single-target damage skill" % basic_attack)
	for effect_id in bot_skill_effects:
		if not skills.has(bot_skill_effects[effect_id]):
			problems.append("bot effect %s maps to undefined skill %s" % [effect_id, bot_skill_effects[effect_id]])
	if power_percent_per_level < 0:
		problems.append("power_percent_per_level may not be negative")
	if max_guard_percent < 0 or max_guard_percent > 100:
		problems.append("guard max_percent must be 0 to 100")
	for id in skills:
		var s: CombatSkill = skills[id]
		if not s.effect in CombatSkill.EFFECTS:
			problems.append("skill %s has unknown effect %s" % [id, s.effect])
		if not s.target in CombatSkill.TARGETS:
			problems.append("skill %s has unknown target %s" % [id, s.target])
		elif s.is_damage() != s.targets_opponents():
			problems.append("skill %s: damage skills target opponents, others their own side" % id)
	return problems


## A copy of this tuning that plays with `p_variants`. Shares the skills.
func with_variants(p_variants: FightVariants) -> CombatTuning:
	var t: CombatTuning = CombatTuning.new()
	for prop in get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			t.set(prop.name, get(prop.name))
	t.variants = p_variants
	return t


## True for a skill that can always be used: free, and hits one opponent.
static func is_basic_attack(s: CombatSkill) -> bool:
	return s.is_damage() and s.target == CombatSkill.TARGET_OPPONENT and s.energy_cost == 0


## The skill `effect_id`'s bot skill fights with, or "" when none is defined.
func combat_skill_for_effect(effect_id: String) -> String:
	return bot_skill_effects.get(effect_id, "")


## Skill `id` as this tuning's switches have it: the strike-cost switch may
## change the basic attack's cost (EnergyRules). Null for an unknown id.
func skill(id: String) -> CombatSkill:
	var s: CombatSkill = skills.get(id)
	if s == null:
		return null
	var cost := EnergyRules.cost_of(id, s.energy_cost, self)
	if cost == s.energy_cost:
		return s
	var c := s.at_level(s.level, "", 0, 100)
	c.energy_cost = cost
	return c


## Gauge a unit must fill before it acts, by the speed-range switch (SpeedRules).
func turn_threshold() -> int:
	return SpeedRules.threshold(self)


## True when bot skills grow by named ranks rather than flat levels.
func uses_ranks() -> bool:
	return variants.is_chosen(FightVariants.SKILL_PROGRESSION, FightVariants.PROGRESSION_RANKS) and skill_ranks != null


## Skill `id` as a unit with `level` in it holds it, named `p_name` ("" keeps
## the tuning's name): by rank or by flat level, as the skill-progression
## switch says. Null for an unknown id.
func skill_at(id: String, level: int, p_name := "") -> CombatSkill:
	var base := skill(id)
	if base == null:
		return null
	if uses_ranks():
		return skill_ranks.apply(base, level, p_name, max_guard_percent)
	return base.at_level(level, p_name, power_percent_per_level, max_guard_percent)
