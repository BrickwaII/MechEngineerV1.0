class_name ArchetypeRules
extends RefCounted
## What an enemy archetype (EnemyArchetype; data/combat/archetypes.json) does
## in a fight (combat rework S5). Fight calls these; IntentPlanner reads the
## same state to plan.
##
## - Intent pattern: Combatant.pattern_step is the step the unit takes next.
##   A decision moves it on, except a wait on an action step (the unit is
##   still saving up for that action).
## - Wind-up (the Charger): a wait taken on a wind_up step commits the hit it
##   telegraphs, on its target (Combatant.committed), and holds the wait until
##   wind_up_opponent_actions opponent decisions have resolved
##   (Combatant.telegraph_wait), so a lethal hit is always seen at least one
##   ally action in advance. The unit then lands the hit; if its target went
##   down meanwhile it re-aims the same hit (retarget()).
## - Stagger (StaggerRules) cancels the committed hit and starts the pattern
##   over: the wind-up is lost. TODO(decision: stagger-intent).
## - Growth (the Scaler): each decision the unit makes adds
##   scaling_percent_per_action of its base stats (Combatant.base_stats),
##   raising a GROWTH event. A Staggered unit's lost turn does not grow it.
##
## Every rule here is deterministic and applies only to units with an
## archetype, so enemies without one fight exactly as before.


## Moves `unit`'s pattern on after its decision `action` resolved, commits a
## wind-up and grows a Scaler. Called by Fight.submit() once the action has
## landed.
static func after_decision(fight: Fight, unit: Combatant, action: FightAction) -> void:
	var a := unit.archetype
	if a == null or not unit.is_alive():
		return
	var step := a.step_at(unit.pattern_step)
	if action.kind == FightAction.Kind.WAIT:
		if step == EnemyArchetype.STEP_WIND_UP:
			_commit(fight, unit, action.skill_id, action.target_id, a.wind_up_opponent_actions)
			unit.pattern_step += 1
		elif step == EnemyArchetype.STEP_PLAN:
			unit.pattern_step += 1
	else:
		unit.committed = null
		unit.pattern_step += 1
	if a.scales():
		grow(fight, unit)


## A decision by `actor` has resolved: every opponent of it winding up
## counts it toward its telegraph.
static func count_telegraph(fight: Fight, actor: Combatant) -> void:
	for c in fight.combatants:
		if c.side != actor.side and c.telegraph_wait > 0:
			c.telegraph_wait -= 1


## A Stagger cancels `unit`'s committed hit and starts its pattern over.
static func on_stagger(unit: Combatant) -> void:
	if unit.archetype == null:
		return
	unit.committed = null
	unit.telegraph_wait = 0
	unit.pattern_step = 0


## Re-aims `unit`'s committed hit when its target is down: the same skill at
## the best living target the planner sees. Returns true when it re-aimed.
static func retarget(fight: Fight, unit: Combatant, planner: IntentPlanner) -> bool:
	var hit := unit.committed
	if hit == null:
		return false
	var target := fight.combatant(hit.target_id())
	if target != null and target.is_alive():
		return false
	var best: UnitIntent = null
	for o in planner.rank_unpatterned(fight, unit):
		if o.skill_id() == hit.skill_id() and o.kind != UnitIntent.Kind.HEAL:
			best = o
			break
	if best == null:
		unit.committed = null
		return true
	unit.committed = UnitIntent.new(unit.id, UnitIntent.Kind.ATTACK,
		FightAction.use(hit.skill_id(), best.target_id()), best.amount, best.score)
	return true


## One growth step for a Scaler: its stats become base + base x percent x
## growth / 100 for each scaled stat (rounded down), and a GROWTH event says so.
@warning_ignore("integer_division")
static func grow(fight: Fight, unit: Combatant) -> void:
	var a := unit.archetype
	unit.growth += 1
	var base := unit.base_stats
	var grown := UnitStats.new(base.hp, base.attack, base.defense, base.speed, base.elasticity, base.battery_capacity)
	var changes := PackedStringArray()
	for stat in a.scaling_percent_per_action:
		var before: int = unit.stats.get(stat)
		var value: int = base.get(stat) + base.get(stat) * a.scaling_percent_per_action[stat] * unit.growth / 100
		grown.set(stat, maxi(0, value))
		if grown.get(stat) != before:
			changes.append("%s %d -> %d" % [stat, before, grown.get(stat)])
	unit.set_stats(grown)
	var e := FightEvent.new(FightEvent.Kind.GROWTH, fight.action_count, unit.id, unit.id, "")
	e.amount = unit.growth
	e.hp_before = unit.hp
	e.max_hp = unit.max_hp
	fight.raise_event(e)
	fight.add_log("%s grows (x%d)%s" % [
		unit.display_name, unit.growth, ": " + ", ".join(changes) if not changes.is_empty() else ""])


static func _commit(fight: Fight, unit: Combatant, skill_id: String, target_id: String, telegraph: int) -> void:
	var skill := unit.skill(skill_id)
	var target := fight.combatant(target_id)
	if skill == null or not skill.targets_opponents():
		return
	var amount := 0
	if target != null and target.is_alive() and target.side != unit.side:
		amount = DamageRules.action_damage_to(unit, target, skill, fight.tuning)
	unit.committed = UnitIntent.new(unit.id, UnitIntent.Kind.ATTACK, FightAction.use(skill_id, target_id), amount)
	unit.telegraph_wait = maxi(0, telegraph)
	fight.add_log("%s winds up %s%s" % [unit.display_name, skill.display_name,
		" at %s" % target.display_name if target != null else ""])
