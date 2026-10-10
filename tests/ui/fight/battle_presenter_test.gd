extends GdUnitTestSuite
## BattlePresenter: actions play one at a time, meters move when the hit
## lands, enemies wait for the animation, and the input never waits.

const Helpers := preload("res://tests/ui/fight/fight_ui_helpers.gd")

var _screen: BattleScreen


func before_test() -> void:
	_screen = auto_free(Helpers.screen())
	add_child(_screen)
	await get_tree().process_frame


## Plays beats by hand, as a display would, with no effects.
func _animated() -> BattlePresenter:
	var p := _screen.presenter
	p.headless = false
	p.effects_enabled = false
	p.settings = GameSettings.new()
	p.set_process(false)
	return p


func _strike_weakest() -> Combatant:
	var target := _screen.fight.living(Combatant.Side.ENEMY)[0]
	_screen.skill_buttons["strike"].pressed.emit()
	Helpers.click(_screen.unit_panels[target.id])
	return target


func test_headless_beats_resolve_at_once() -> void:
	var target := _strike_weakest()
	assert_bool(_screen.presenter.is_busy()).is_false()
	assert_int(int(_screen.unit_panels[target.id].hp_bar.value)).is_equal(target.hp)
	assert_array(_screen.presenter.last_sounds).contains([&"skill_strike"])


func test_the_meter_holds_until_the_hit_lands() -> void:
	var p := _animated()
	var target := _screen.fight.living(Combatant.Side.ENEMY)[0]
	var hp_before := target.hp
	_strike_weakest()
	assert_int(target.hp).is_less(hp_before)
	assert_bool(p.is_busy()).is_true()
	var bar = _screen.unit_panels[target.id].hp_bar
	assert_int(int(bar.value)).is_equal(hp_before)
	p.advance(0.0)
	var beat := p.current
	p.advance(beat.impact_at() - 0.01)
	assert_int(int(bar.value)).is_equal(hp_before)
	p.advance(0.02)
	assert_int(int(bar.value)).is_equal(target.hp)
	p.advance(beat.duration())
	assert_bool(p.current == null or p.current != beat).is_true()


func test_the_next_enemy_waits_for_the_animation_but_the_fight_has_moved_on() -> void:
	var p := _animated()
	var actions := _screen.fight.action_count
	_strike_weakest()
	assert_int(_screen.fight.action_count).is_equal(actions + 1)
	if _screen.handler.is_enemy_turn():
		_screen._process(10.0)
		assert_int(_screen.fight.action_count).is_equal(actions + 1)
	while p.is_busy():
		p.advance(0.1)
	if _screen.handler.is_enemy_turn():
		_screen._process(10.0)
		assert_int(_screen.fight.action_count).is_greater(actions + 1)


func test_actions_queue_in_order_and_the_meters_settle_after() -> void:
	var p := _animated()
	var first := _strike_weakest()
	var queued := p.queue.size() + (1 if p.current != null else 0)
	assert_int(queued).is_greater_equal(1)
	while p.is_busy():
		p.advance(0.05)
	assert_dict(p.shown_hp_by_id).is_empty()
	assert_dict(p.shown_energy_by_id).is_empty()
	await get_tree().process_frame
	assert_int(int(_screen.unit_panels[first.id].hp_bar.value)).is_equal(first.hp)


func test_a_maxed_skill_plays_fuller_sound_and_more_projectiles() -> void:
	var p := _screen.presenter
	var tuning := CombatTuning.load_default()
	var events: Array[FightEvent] = []
	var used := FightEvent.new(FightEvent.Kind.SKILL, 1, "stub_bolt", "", "heavy_strike")
	var hit := FightEvent.new(FightEvent.Kind.HIT, 1, "stub_bolt", _screen.fight.living(Combatant.Side.ENEMY)[0].id, "heavy_strike")
	hit.amount = 1
	hit.max_hp = 100
	hit.hp_before = 50
	hit.hp_after = 49
	events.assign([used, hit])
	var low := p.present(events)
	var low_sounds := p.last_sounds.duplicate()
	var low_pause := p.last_hit_pause
	var high_beat := BattleBeat.from_events(_screen.fight, events)
	high_beat.fx = SkillFx.for_skill(tuning.skill("heavy_strike").at_level(
		SkillFx.max_level(), "Overcharge Shot", tuning.power_percent_per_level, tuning.max_guard_percent))
	p.queue.append(high_beat)
	p._drain_at_once()
	assert_int(p.last_sounds.size()).is_greater(low_sounds.size())
	assert_int(p.last_projectiles).is_greater(1)
	assert_str(low_pause).is_equal("light")
	assert_str(p.last_hit_pause).is_equal("heavy")
	assert_float(high_beat.duration()).is_equal(low.duration())
