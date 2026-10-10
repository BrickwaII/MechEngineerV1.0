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
