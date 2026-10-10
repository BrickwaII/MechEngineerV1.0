class_name FightCommandHandler
extends RefCounted
## Applies FightCommands to a Fight: the one place player input turns into
## FightActions. Holds the selection (bot, then skill, then target) and plays
## enemy turns with a policy.
##
##   var handler := FightCommandHandler.new(fight)
##   handler.apply(FightCommand.select_skill("strike"))
##   handler.apply(FightCommand.select_target("drone#1"))  # submits, enemies act
##
## In ATB wait mode only the pending unit may act. Any living bot may be
## selected to look at it, but only the pending one takes skills and targets.
## When the pending unit's turn comes up it is selected automatically.

## Emitted after every change to the fight or the selection.
signal changed
## Emitted after each resolved action, player or enemy. `tag` is the fight's
## action tag, "<unit id>:<skill id>" or "<unit id>:wait".
signal action_resolved(actor_id: String, tag: String)
## Emitted once, when the fight ends. A fight can already be over when the
## handler is built (an invalid request), so check fight.is_over() too.
signal fight_over(result: FightResult)

var fight: Fight
var enemy_policy: FightPolicy
## When true, enemy turns resolve straight after each player action. When
## false, call resolve_enemy_turn() to play them one at a time (for pacing).
var auto_resolve_enemies: bool
var selected_bot_id := ""
var selected_skill_id := ""

var _fallback := SimpleFightPolicy.new()
var _rng := RandomNumberGenerator.new()
var _over_sent := false


func _init(p_fight: Fight, p_enemy_policy: FightPolicy = null, p_auto_resolve_enemies := true) -> void:
	fight = p_fight
	enemy_policy = p_enemy_policy if p_enemy_policy != null else _fallback
	auto_resolve_enemies = p_auto_resolve_enemies
	# Seeded like HeadlessFightRunner, so a policy that draws replays exactly.
	_rng.seed = hash("policy:%d" % fight.fight_seed)
	_next_turn()
	if auto_resolve_enemies:
		resolve_enemy_turns()


## Applies one command. Returns "" when it was accepted, else why not; a
## refused command changes nothing.
func apply(command: FightCommand) -> String:
	if command == null:
		return "no command"
	var problem := ""
	match command.kind:
		FightCommand.Kind.SELECT_BOT:
			problem = _select_bot(command.arg)
		FightCommand.Kind.SELECT_SKILL:
			problem = _select_skill(command.arg)
		FightCommand.Kind.SELECT_TARGET:
			problem = _select_target(command.arg)
		FightCommand.Kind.WAIT:
			problem = _wait(command.arg, command.ticks)
		FightCommand.Kind.CANCEL:
			problem = _cancel()
	if problem.is_empty():
		changed.emit()
	return problem


## The unit whose turn it is, or null once the fight is over.
func actor() -> Combatant:
	return fight.pending_actor


func is_player_turn() -> bool:
	return actor() != null and actor().side == Combatant.Side.PLAYER


func is_enemy_turn() -> bool:
	return actor() != null and actor().side == Combatant.Side.ENEMY


func selected_bot() -> Combatant:
	return fight.combatant(selected_bot_id)


## True when the selection is waiting for a target.
func is_choosing_target() -> bool:
	return not selected_skill_id.is_empty()


## Why the pending bot cannot use `skill_id` now, or "" when it can.
func skill_problem(skill_id: String) -> String:
	if not is_player_turn():
		return "not your turn"
	var unit := actor()
	var skill := unit.skill(skill_id)
	if skill == null:
		return "%s has no skill %s" % [unit.display_name, skill_id]
	if not unit.can_afford(skill):
		return "%s needs %d energy for %s" % [unit.display_name, skill.energy_cost, skill.display_name]
	return ""


## Why the selected skill may not hit `target_id`, or "" when it may.
func target_problem(target_id: String) -> String:
	if not is_choosing_target():
		return "choose a skill first"
	return fight.check_action(FightAction.use(selected_skill_id, target_id))


## The skill a WAIT with no skill named waits for: the selected skill, else
## the cheapest skill the pending bot cannot afford yet but can one day.
## "" when there is none.
func default_wait_skill() -> String:
	if not selected_skill_id.is_empty():
		return selected_skill_id
	if not is_player_turn():
		return ""
	var unit := actor()
	var best: CombatSkill = null
	for skill in unit.skills():
		if unit.can_afford(skill) or skill.energy_cost_milli() > unit.max_energy_milli:
			continue
		if best == null or skill.energy_cost < best.energy_cost:
			best = skill
	return best.id if best != null else ""


## Plays the pending enemy's turn with the enemy policy. Returns false when it
## is not an enemy's turn.
func resolve_enemy_turn() -> bool:
	if not is_enemy_turn():
		return false
	var unit := actor()
	var problem := fight.submit(enemy_policy.choose(fight, unit, _rng))
	if not problem.is_empty():
		# A broken policy must not stall the fight, as in HeadlessFightRunner.
		fight.log_lines.append("  policy refused (%s), %s acts by default" % [problem, unit.display_name])
		problem = fight.submit(_fallback.choose(fight, unit, _rng))
		assert(problem.is_empty(), problem)
	_after_action(unit)
	_next_turn()
	changed.emit()
	return true


## Plays enemy turns until a bot must decide or the fight ends.
func resolve_enemy_turns() -> void:
	while resolve_enemy_turn():
		pass


func _select_bot(bot_id: String) -> String:
	var unit := fight.combatant(bot_id)
	if unit == null or unit.side != Combatant.Side.PLAYER:
		return "no bot %s" % bot_id
	if not unit.is_alive():
		return "%s is down" % unit.display_name
	selected_bot_id = bot_id
	selected_skill_id = ""
	return ""


func _select_skill(skill_id: String) -> String:
	var problem := _check_selected_bot_acts()
	if not problem.is_empty():
		return problem
	problem = skill_problem(skill_id)
	if not problem.is_empty():
		return problem
	# A self-only skill has one possible target: use it straight away.
	if actor().skill(skill_id).target == CombatSkill.TARGET_SELF:
		_submit(FightAction.use(skill_id, actor().id))
		return ""
	selected_skill_id = skill_id
	return ""


func _select_target(target_id: String) -> String:
	var problem := _check_selected_bot_acts()
	if not problem.is_empty():
		return problem
	problem = target_problem(target_id)
	if not problem.is_empty():
		return problem
	_submit(FightAction.use(selected_skill_id, target_id))
	return ""


func _wait(skill_id: String, ticks := 0) -> String:
	var problem := _check_selected_bot_acts()
	if not problem.is_empty():
		return problem
	if skill_id.is_empty():
		skill_id = default_wait_skill()
	# An exact wait needs no skill to save up for; it names the first one.
	if skill_id.is_empty() and ticks > 0 and not actor().skill_ids.is_empty():
		skill_id = actor().skill_ids[0]
	if skill_id.is_empty():
		return "nothing to wait for: every skill is ready"
	var action := FightAction.wait_exact(skill_id, ticks)
	problem = fight.check_action(action)
	if not problem.is_empty():
		return problem
	_submit(action)
	return ""


## Steps the selection back: target choice to skill choice, then back to the
## bot whose turn it is.
func _cancel() -> String:
	if not selected_skill_id.is_empty():
		selected_skill_id = ""
		return ""
	if is_player_turn() and selected_bot_id != actor().id:
		selected_bot_id = actor().id
		return ""
	return "nothing to cancel"


func _check_selected_bot_acts() -> String:
	if fight.is_over():
		return "the fight is over"
	if not is_player_turn():
		return "not your turn"
	if selected_bot_id != actor().id:
		var unit := selected_bot()
		return "%s is not ready to act" % (unit.display_name if unit != null else "no bot")
	return ""


func _submit(action: FightAction) -> void:
	var unit := actor()
	var problem := fight.submit(action)
	assert(problem.is_empty(), problem)
	_after_action(unit)
	_next_turn()
	if auto_resolve_enemies:
		resolve_enemy_turns()


func _after_action(unit: Combatant) -> void:
	action_resolved.emit(unit.id, fight.action_tags[-1])


## Runs time to the next decision and selects the bot that has to make it.
func _next_turn() -> void:
	selected_skill_id = ""
	var unit := fight.advance()
	if unit != null and unit.side == Combatant.Side.PLAYER:
		selected_bot_id = unit.id
	elif fight.is_over():
		selected_bot_id = ""
		if not _over_sent:
			_over_sent = true
			fight_over.emit(fight.result())
