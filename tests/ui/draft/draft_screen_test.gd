extends GdUnitTestSuite
## The draft screen, headless. Input events do not arrive in headless mode,
## so these press the cards and buttons through their signals.

const SCENE := preload("res://ui/draft/draft_screen.tscn")

var _runner: GdUnitSceneRunner
var _screen: DraftScreen


func before_test() -> void:
	_screen = SCENE.instantiate()
	_screen.draft_seed = 5
	_runner = scene_runner(auto_free(_screen))
	await _runner.simulate_frames(2)


func test_one_card_per_drafted_bot() -> void:
	var tuning := BotTuning.load_default()
	assert_int(_screen.cards.size()).is_equal(tuning.draft_size)
	assert_bool(_screen.start_button.disabled).is_true()
	assert_str(_screen.count_label.text).is_equal("0 / %d picked" % tuning.squad_size)


func test_clicking_cards_picks_a_squad_and_starts_the_fight() -> void:
	var chosen: Array = []
	_screen.squad_chosen.connect(func(squad: Array[SquadMemberSummary]) -> void: chosen.append(squad))
	var bots := _screen.picker.bots()
	var size := _screen.picker.squad_size()
	for i in size:
		_screen.cards[bots[i].id].pressed.emit()
	assert_bool(_screen.cards[bots[0].id].button_pressed).is_true()
	assert_bool(_screen.start_button.disabled).is_false()
	_screen.start_button.pressed.emit()
	assert_int(chosen.size()).is_equal(1)
	var squad: Array[SquadMemberSummary] = chosen[0]
	assert_int(squad.size()).is_equal(size)
	assert_str(squad[0].id).is_equal(bots[0].id)


func test_a_second_click_drops_the_bot() -> void:
	var id := _screen.picker.bots()[0].id
	_screen.cards[id].pressed.emit()
	_screen.cards[id].pressed.emit()
	assert_bool(_screen.picker.is_picked(id)).is_false()
	assert_bool(_screen.cards[id].button_pressed).is_false()


func test_start_does_nothing_until_the_squad_is_full() -> void:
	var chosen: Array = []
	_screen.squad_chosen.connect(func(squad: Array[SquadMemberSummary]) -> void: chosen.append(squad))
	_screen.cards[_screen.picker.bots()[0].id].pressed.emit()
	_screen.start()
	assert_array(chosen).is_empty()


func test_each_card_shows_its_bot_sprite_from_the_manifest() -> void:
	for bot in _screen.picker.bots():
		var card := _screen.cards[bot.id] as DraftCard
		assert_object(card.sprite).is_not_null()
		assert_str(card.sprite.unit_id).is_equal(DraftCard.ALLY_UNIT)
		assert_dict(card.sprite.look).is_equal(SpriteManifest.ally_look(DraftCard.ALLY_UNIT, DraftCard.look_seed(bot.id)))
	# The same bot always gets the same look.
	assert_int(DraftCard.look_seed("bot_1")).is_equal(DraftCard.look_seed("bot_1"))


func test_cards_flip_in_one_after_another() -> void:
	var screen: DraftScreen = auto_free(SCENE.instantiate())
	add_child(screen)
	await await_idle_frame()
	var cards := screen.picker.bots().map(func(b: Bot) -> DraftCard: return screen.cards[b.id])
	assert_float(cards[0].face.scale.x).is_less(1.0)
	await await_millis(int(ScreenFeel.number("draft.flip_ms") + ScreenFeel.number("draft.flip_stagger_ms") * cards.size()) + 200)
	for card: DraftCard in cards:
		assert_float(card.face.scale.x).is_equal_approx(1.0, 1e-3)
	screen.get_parent().remove_child(screen)


func test_a_hovered_card_lifts_and_settles_when_left() -> void:
	var card := _screen.cards[_screen.picker.bots()[0].id] as DraftCard
	card.mouse_entered.emit()
	await await_millis(int(ScreenFeel.number("draft.lift_ms")) + 80)
	assert_float(card.lift()).is_equal_approx(ScreenFeel.number("draft.lift_px"), 0.01)
	assert_float(card.face.position.y).is_equal_approx(-ScreenFeel.number("draft.lift_px"), 0.01)
	card.mouse_exited.emit()
	await await_millis(int(ScreenFeel.number("draft.lift_ms")) + 80)
	assert_float(card.lift()).is_equal(0.0)


func test_picked_bots_fill_the_squad_bar_in_pick_order() -> void:
	var bots := _screen.picker.bots()
	assert_int(_screen.slots.size()).is_equal(_screen.picker.squad_size())
	_screen.cards[bots[2].id].pressed.emit()
	_screen.cards[bots[0].id].pressed.emit()
	var expected: Array[String] = [bots[2].id, bots[0].id]
	while expected.size() < _screen.slots.size():
		expected.append("")
	assert_array(_screen.slot_bot_ids()).is_equal(expected)
	assert_str((_screen.cards[bots[0].id] as DraftCard).badge.text).is_equal("2")
	# A sprite flies into the slot and lands.
	await await_millis(int(ScreenFeel.number("draft.snap_ms")) + 300)
	var landed := _screen.slots[1].get_children().filter(func(c: Node) -> bool: return c is UnitSprite)
	assert_int(landed.size()).is_equal(1)
	assert_bool(landed[0].visible).is_true()
	# Dropping the first pick slides the second into slot 1.
	_screen.cards[bots[2].id].pressed.emit()
	assert_str(_screen.slot_bot_ids()[0]).is_equal(bots[0].id)
	assert_str(_screen.slot_bot_ids()[1]).is_empty()
