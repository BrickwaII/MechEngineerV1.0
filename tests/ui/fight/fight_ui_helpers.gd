extends RefCounted
## Builders shared by the fight screen tests.

const BATTLE_SCENE := preload("res://ui/fight/battle_screen.tscn")
const SEED := 7


static func request(level := 1) -> FightRequest:
	return FightRequest.new(FightRequest.Kind.ATTACK, "test_territory", level, StubSquadProvider.new().get_squad())


## Screen tuning with no enemy delay, so enemies act on the next frame.
static func fast_tuning() -> FightScreenTuning:
	var t := FightScreenTuning.load_default()
	t.enemy_turn_delay_seconds = 0.0
	return t


static func screen(level := 1) -> BattleScreen:
	var s: BattleScreen = BATTLE_SCENE.instantiate()
	s.setup(request(level), SEED, fast_tuning())
	return s


static func click(panel: Control, button := MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	panel._gui_input(event)


## One player turn by mouse: the strongest affordable skill button, then a
## click on the weakest enemy. The choice SimpleFightPolicy would make.
static func play_turn_by_mouse(s: BattleScreen) -> void:
	var fight := s.fight
	var actor := s.handler.actor()
	var best := ""
	for id in actor.skill_ids:
		if s.handler.skill_problem(id).is_empty() and (best.is_empty()
				or fight.tuning.skill(id).power_percent > fight.tuning.skill(best).power_percent):
			best = id
	var target: Combatant = null
	for c in fight.opponents_of(actor):
		if target == null or c.hp < target.hp:
			target = c
	s.skill_buttons[best].pressed.emit()
	click(s.unit_panels[target.id])


## Bolt, one strong fast bot, against two Warden Mechs (supportive, by
## data/combat/intent/enemy_personalities.json) that can Repair each other.
static func healer_request() -> FightRequest:
	var squad: Array[SquadMemberSummary] = [SquadMemberSummary.new(
		"bolt", "Bolt", 60, 60, "aggressive", UnitStats.new(60, 14, 4, 20, 0, 10))]
	return FightRequest.new(FightRequest.Kind.ATTACK, "test_territory", 1, squad)


static func healer_table() -> EnemyTable:
	var levels := []
	for level in range(FightRequest.MIN_DEFENSE_LEVEL, FightRequest.MAX_DEFENSE_LEVEL + 1):
		levels.append({"level": level, "count": 2, "pool": ["warden_mech"], "rewards": {"energy": 3, "material": 1}})
	return EnemyTable.from_dict({
		"enemies": {"warden_mech": {
			"name": "Warden Mech", "hp": 40, "attack": 9, "defense": 1, "speed": 4, "elasticity": 0,
			"battery_capacity": 10, "skills": ["strike", "repair"]}},
		"levels": levels,
	})


static func healer_screen() -> BattleScreen:
	var s: BattleScreen = BATTLE_SCENE.instantiate()
	s.setup(healer_request(), SEED, fast_tuning(), null, healer_table())
	return s
