extends GdUnitTestSuite
## The battle screen's numbers are the fight's numbers. Over many seeded
## fights, every previewed number (arrow badges, KO marks, hp and energy
## slices, the intents and turn order after a choice) is checked against what
## the fight then resolves. Player choices are drawn at random from every
## legal action (a seeded draw), so waits, heals, guards and sweeps all come up.

const T := preload("res://tests/fight/intent/intent_test_helpers.gd")
const SEEDS := 12
const MAX_DECISIONS := 120

var _events: Array[FightEvent] = []
var _checked := {"player": 0, "enemy": 0, "ko": 0, "heal": 0, "guard": 0, "order_shift": 0, "status": 0, "multi_hit": 0}


func test_previews_equal_resolutions_over_many_seeded_fights() -> void:
	for seed_value in range(1, SEEDS + 1):
		for level in range(FightRequest.MIN_DEFENSE_LEVEL, FightRequest.MAX_DEFENSE_LEVEL + 1):
			var request := FightRequest.new(
				FightRequest.Kind.ATTACK, "test_territory", level, StubSquadProvider.new().get_squad())
			_play(Fight.new(request, seed_value), seed_value * 31 + level)
	# Heal intents: two Warden Mechs that Repair each other.
	for seed_value in range(1, 6):
		_play(T.healer_fight(), seed_value, T.healer_planner())
	# Statuses and multi-hit: both sides hold Shred (Exposed) and Heavy Strike
	# (its payoff), so Exposed is applied, used up and worn off.
	for seed_value in range(1, 21):
		_play(_shred_fight(), seed_value * 7)
	assert_int(_checked.player).is_greater(500)
	assert_int(_checked.enemy).is_greater(500)
	assert_int(_checked.ko).is_greater(20)
	assert_int(_checked.heal).is_greater(10)
	assert_int(_checked.guard).is_greater(10)
	assert_int(_checked.status).is_greater(20)
	assert_int(_checked.multi_hit).is_greater(20)


## Two allies and two enemies, every one holding Strike, Shred and Heavy
## Strike.
static func _shred_fight() -> Fight:
	var tuning := T.tuning_with_repair()
	tuning.player_skills.assign(["strike", "shred", "heavy_strike"])
	var skills := ["strike", "shred", "heavy_strike"]
	return T.fight(
		[{"id": "bolt", "stats": T.stats(40, 9, 3, 9, 8)}, {"id": "ace", "stats": T.stats(36, 11, 2, 5, 10)}],
		[{"id": "brute#1", "stats": T.stats(45, 8, 3, 7, 8), "skills": skills},
			{"id": "brute#2", "stats": T.stats(30, 7, 2, 10, 6), "skills": skills}], tuning)


func _play(fight: Fight, rng_seed: int, planner: IntentPlanner = null) -> void:
	planner = planner if planner != null else IntentPlanner.new()
	var preview := FightPreview.new(planner)
	var policy := IntentFightPolicy.new(planner)
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	fight.event_raised.connect(_on_event)
	var decisions := 0
	while not fight.is_over() and decisions < MAX_DECISIONS:
		var actor := fight.advance()
		if actor == null:
			break
		decisions += 1
		if actor.side == Combatant.Side.PLAYER:
			_player_turn(fight, preview, planner, rng)
		else:
			_enemy_turn(fight, planner, policy, preview.rules)
	fight.event_raised.disconnect(_on_event)


func _on_event(e: FightEvent) -> void:
	_events.append(e)


func _player_turn(fight: Fight, preview: FightPreview, planner: IntentPlanner, rng: RandomNumberGenerator) -> void:
	var options := _legal_actions(fight)
	var action: FightAction = options[rng.randi_range(0, options.size() - 1)]
	var actor := fight.pending_actor
	var choice := preview.preview_choice(fight, action)
	assert_bool(choice.is_allowed()).is_true()
	var badges := BattleReadout.choice_badges(fight, action, choice)
	var hp_before := {}
	var energy_before := {}
	var statuses_before := {}
	for c in fight.combatants:
		hp_before[c.id] = c.hp
		statuses_before[c.id] = FightPreview.status_texts(c)
		energy_before[c.id] = c.energy_milli
	var current_order := fight.upcoming(preview.order_length)
	var energy_shown := BattleReadout.energy_after(actor, actor.skill(action.skill_id)) if action.kind == FightAction.Kind.SKILL else -1
	_events.clear()
	assert_str(fight.submit(action)).is_empty()
	var context := "seed %d action %d: %s %s" % [fight.fight_seed, fight.action_count, actor.id, action]
	# Hp slices: every unit's hp after equals the preview; untouched units keep theirs.
	for c in fight.combatants:
		var effect := choice.effect_on(c.id)
		if effect != null:
			assert_int(c.hp).override_failure_message(context).is_equal(effect.hp_after.value)
			assert_bool(effect.would_go_down()).override_failure_message(context).is_equal(not c.is_alive())
		else:
			assert_int(c.hp).override_failure_message(context).is_equal(hp_before[c.id])
		if choice.guard_changes.has(c.id):
			assert_int(c.guard_percent).override_failure_message(context).is_equal(choice.guard_changes[c.id])
		# Statuses after: as previewed, and unchanged where none was previewed.
		var statuses_after := FightPreview.status_texts(c)
		if choice.status_changes.has(c.id):
			assert_array(statuses_after).override_failure_message(context).is_equal(choice.status_changes[c.id])
			_checked.status += 1
		else:
			assert_array(statuses_after).override_failure_message(context).is_equal(statuses_before[c.id])
		if choice.energy_after.has(c.id):
			assert_int(c.energy()).override_failure_message(context).is_equal(choice.energy_after[c.id])
		else:
			assert_int(c.energy_milli).override_failure_message(context).is_equal(energy_before[c.id])
	# The energy slice drawn before a target is chosen.
	if energy_shown >= 0:
		assert_int(actor.energy()).override_failure_message(context).is_equal(energy_shown)
	# Arrow badges and KO marks.
	_check_badges(badges, context)
	# What the screen shows next: intents and their arrows, and the NEXT bar.
	fight.advance()
	var intents_now := planner.plan_all(fight)
	assert_int(intents_now.size()).override_failure_message(context).is_equal(choice.intents_after.size())
	for id: String in intents_now:
		assert_bool(intents_now[id].same_as(choice.intents_after.get(id))).override_failure_message(context).is_true()
		assert_int(intents_now[id].amount).override_failure_message(context).is_equal(choice.intents_after[id].amount)
	var real_badges := BattleReadout.intent_badges(fight, intents_now, preview.rules)
	var shown_badges := BattleReadout.intent_badges(choice.fight_after, choice.intents_after, preview.rules)
	assert_array(_texts(shown_badges)).override_failure_message(context).is_equal(_texts(real_badges))
	if not fight.is_over():
		var order := fight.upcoming(preview.order_length)
		assert_array(_ids(choice.order_after)).override_failure_message(context).is_equal(_ids(order))
		var shown := BattleReadout.order_with_choice(current_order, choice)
		if not BattleReadout.same_order(shown, current_order):
			_checked.order_shift += 1
	_checked.player += 1


func _enemy_turn(fight: Fight, planner: IntentPlanner, policy: IntentFightPolicy, rules: PreviewRules) -> void:
	var actor := fight.pending_actor
	# The intent the screen telegraphs at this decision, and its arrows.
	var intent: UnitIntent = planner.plan_all(fight).get(actor.id)
	var action := policy.choose(fight, actor, null)
	var context := "seed %d action %d: %s" % [fight.fight_seed, fight.action_count + 1, actor.id]
	assert_object(intent).override_failure_message(context).is_not_null()
	assert_str(str(action)).override_failure_message(context).is_equal(str(intent.action))
	var badges := BattleReadout.badges_for_intent(fight, intent, rules)
	_events.clear()
	assert_str(fight.submit(action)).is_empty()
	if intent.kind == UnitIntent.Kind.WAIT:
		assert_bool(_events.any(func(e: FightEvent) -> bool: return e.kind == FightEvent.Kind.WAIT)).is_true()
	else:
		_check_badges(badges, context)
	_checked.enemy += 1


## Each badge against the events its action raised.
func _check_badges(badges: Array[ArrowBadge], context: String) -> void:
	for b in badges:
		var line := "%s, badge %s" % [context, b]
		match b.kind:
			ArrowBadge.ATTACK:
				# Every hit of a multi-hit skill counts toward the one badge.
				var hits := _events.filter(func(e: FightEvent) -> bool:
					return e.kind == FightEvent.Kind.HIT and e.target_id == b.to_id and e.actor_id == b.from_id)
				assert_bool(hits.is_empty()).override_failure_message(line).is_false()
				var total := 0
				for e: FightEvent in hits:
					total += e.amount
				assert_int(total).override_failure_message(line).is_equal(b.amount.value)
				if hits.size() > 1:
					_checked.multi_hit += 1
				var downed := _event(FightEvent.Kind.DOWN, b.to_id) != null
				assert_bool(downed).override_failure_message(line).is_equal(b.knocks_out)
				if downed:
					_checked.ko += 1
			ArrowBadge.HEAL:
				var heal := _event(FightEvent.Kind.HEAL, b.to_id)
				assert_object(heal).override_failure_message(line).is_not_null()
				assert_int(heal.amount).override_failure_message(line).is_equal(b.amount.value)
				_checked.heal += 1
			ArrowBadge.GUARD:
				# A Brace badge reads the BRACE event: damage absorbed, not a percent.
				var guard := _event(FightEvent.Kind.BRACE if b.absorb else FightEvent.Kind.GUARD, b.to_id)
				assert_object(guard).override_failure_message(line).is_not_null()
				assert_int(guard.amount).override_failure_message(line).is_equal(b.amount.value)
				_checked.guard += 1
	# Every hit, heal and guard the action raised had its badge.
	for e in _events:
		var kind: String = {FightEvent.Kind.HIT: ArrowBadge.ATTACK, FightEvent.Kind.HEAL: ArrowBadge.HEAL,
			FightEvent.Kind.GUARD: ArrowBadge.GUARD, FightEvent.Kind.BRACE: ArrowBadge.GUARD}.get(e.kind, "")
		if kind.is_empty():
			continue
		assert_bool(badges.any(func(b: ArrowBadge) -> bool: return b.kind == kind and b.to_id == e.target_id)) \
			.override_failure_message("%s: no badge for %s on %s" % [context, kind, e.target_id]).is_true()


func _event(kind: FightEvent.Kind, target_id: String) -> FightEvent:
	for e in _events:
		if e.kind == kind and e.target_id == target_id:
			return e
	return null


## Every action the pending unit may take: each affordable skill on each legal
## target, and a wait for each skill it could ever afford.
static func _legal_actions(fight: Fight) -> Array[FightAction]:
	var out: Array[FightAction] = []
	var actor := fight.pending_actor
	for skill in actor.skills():
		for c in fight.combatants:
			var a := FightAction.use(skill.id, c.id)
			if fight.check_action(a).is_empty():
				out.append(a)
		var w := FightAction.wait_for(skill.id)
		if fight.check_action(w).is_empty():
			out.append(w)
	return out


static func _texts(list: Array[ArrowBadge]) -> Array[String]:
	var out: Array[String] = []
	for b in list:
		out.append(str(b))
	return out


static func _ids(order: Array[TimelineEntry]) -> Array[String]:
	var out: Array[String] = []
	for e in order:
		out.append("%s%s" % [e.combatant_id, " (wait)" if e.ends_wait else ""])
	return out
