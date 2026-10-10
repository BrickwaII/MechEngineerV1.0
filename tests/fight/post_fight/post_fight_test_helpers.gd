extends RefCounted
## Builders shared by the post-fight tests.

const H := preload("res://tests/fight/fight_test_helpers.gd")

## The sample fight's decisions, in order: [actor id, action].
## Ally a (speed 10) acts on ticks 10, 20, 30; ally b (speed 5) on tick 20,
## then on tick 21 when its wait for overload ends. The foe (speed 1) never
## gets a turn and falls to the fifth hit (15 + 10 + 22 + 15 = 62 hp).
##   #0 t10 a heavy_strike  hit_enemy, first_affordable (first turn, 7 >= 4 energy)
##   #1 t20 a strike        hit_enemy, solo            (nobody on its side acted since #0)
##   #2 t20 b wait overload wait                       (b's first turn: never solo)
##   #3 t21 b overload      hit_enemy, solo            (ends a wait: not first_affordable)
##   #4 t30 a heavy_strike  hit_enemy                  (b acted since #1; could afford it at #1)
const SAMPLE_FOE_HP := 62


## Combat tuning with every number the sample fight depends on pinned, so a
## data change does not silently change the sample.
static func combat_tuning() -> CombatTuning:
	var t := CombatTuning.load_default()
	t.action_threshold = 100
	t.min_charge_per_tick = 1
	t.recharge_milli_per_battery_per_tick = 20
	t.recharge_floor_milli_per_tick = 100
	t.starting_energy_percent = 50
	t.wait_recharge_bonus_percent = 100
	t.defense_percent = 50
	t.min_damage = 1
	t.max_actions = 400
	t.player_skills.assign(["strike", "heavy_strike", "overload"])
	t.skills["strike"] = CombatSkill.new("strike", "Strike", 0, 100)
	t.skills["heavy_strike"] = CombatSkill.new("heavy_strike", "Heavy Strike", 4, 150)
	t.skills["overload"] = CombatSkill.new("overload", "Overload", 9, 220)
	return t


## The post-fight data file, with the drift and level numbers pinned. The
## drift rules are the real ones from data/post_fight/.
static func tuning() -> PostFightTuning:
	var t := PostFightTuning.load_default()
	t.drift_per_push = 0.02
	t.max_drift_per_scale_per_fight = 0.1
	t.uses_per_level = 3
	t.levels_per_step = 1
	t.max_level = 10
	t.combat_skill_effects = {"strike": "damage_single", "heavy_strike": "damage_single_heavy", "overload": ""}
	return t


static func bot(id: String, speed: int, generation := 3) -> Bot:
	var skills: Array[Skill] = [
		Skill.new("Strike", "damage_single", 0, 1),
		Skill.new("Overcharge Shot", "damage_single_heavy", 4, 1),
		Skill.new("Brace", "guard_self", 2, 1),
	]
	return Bot.new(id, id.capitalize(), H.stats(40, 10, 0, speed, 10), Personality.new(generation), skills)


static func fight_for(bots: Array[Bot], foe_hp := SAMPLE_FOE_HP) -> Fight:
	var tuning := combat_tuning()
	var squad: Array[SquadMemberSummary] = []
	for b in bots:
		squad.append(b.to_summary())
	var skills: Array = ["strike"]
	var table := H.table({"foe": H.enemy_def("Foe", H.stats(foe_hp, 1, 0, 1, 0), skills)}, "foe")
	return Fight.new(H.request(squad), 1, tuning, table)


## The scripted steps of the sample fight, in order.
static func sample_steps() -> Array:
	return [
		["a", FightAction.use("heavy_strike", "foe#1")],
		["a", FightAction.use("strike", "foe#1")],
		["b", FightAction.wait_for("overload")],
		["b", FightAction.use("overload", "foe#1")],
		["a", FightAction.use("heavy_strike", "foe#1")],
	]


## Plays `steps` on `fight`, checking each actor. Calls `after_each` (if valid)
## after every decision. Returns "" or the first problem.
static func play(fight: Fight, steps: Array, after_each := Callable()) -> String:
	for step: Array in steps:
		var actor := fight.advance()
		if actor == null:
			return "fight ended before %s acted" % step[0]
		if actor.id != step[0]:
			return "expected %s to act, got %s" % [step[0], actor.id]
		var problem := fight.submit(step[1])
		if not problem.is_empty():
			return problem
		if after_each.is_valid():
			after_each.call()
	return ""
