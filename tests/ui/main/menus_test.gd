extends GdUnitTestSuite
## Menus and identity (UI cleanup PR 5): entry tiles with art, the How to
## play guide, the one-time What's new card, the interface size setting and
## each act's tint and emblem on the map.

const MENU := "res://ui/main/main.tscn"
const RUNS := "user://menus_test_runs"

var _runner: GdUnitSceneRunner


func after_test() -> void:
	DetailModal.close_current()


func _menu() -> MainMenu:
	var m: MainMenu = load(MENU).instantiate()
	m.runs_root = RUNS
	m.show_whats_new = false
	_runner = scene_runner(auto_free(m))
	return m


func test_the_main_menu_starts_with_four_entry_tiles_with_art() -> void:
	var menu := _menu()
	await _runner.simulate_frames(2)
	var tiles: Array = menu.find_child("Tiles", true, false).get_children()
	assert_int(tiles.size()).is_equal(4)
	for t: EntryTile in tiles:
		assert_object(t.art).is_not_null()
		assert_str(t.title_label.text).is_not_empty()
		assert_str(t.line_label.text).is_not_empty()
	assert_object(menu.continue_button).is_same(menu.continue_tile)
	assert_object(menu.load_button).is_not_null()


func test_how_to_play_opens_a_page_per_topic() -> void:
	var menu := _menu()
	await _runner.simulate_frames(2)
	menu.how_to_play_button.pressed.emit()
	assert_bool(DetailModal.is_open()).is_true()
	var ids: Array = DetailModal.current.tabs.ids()
	assert_int(ids.size()).is_equal(HowToPlay.pages().size())
	for p: Dictionary in HowToPlay.pages():
		for line: Dictionary in p["lines"]:
			assert_bool(UiIcons.has(str(line["icon"]))).override_failure_message(str(line["icon"])).is_true()


func test_whats_new_shows_once_per_id() -> void:
	var s := GameSettings.new()
	assert_bool(WhatsNewCard.is_due(s)).is_true()
	var host: Control = auto_free(Control.new())
	add_child(host)
	var m := WhatsNewCard.open(host, s)
	assert_object(m.find_child("Feedback", true, false)).is_not_null()
	m.close()
	assert_str(s.whats_new_seen).is_equal(str(WhatsNewCard.data()["id"]))
	assert_bool(WhatsNewCard.is_due(s)).is_false()
	for line: Dictionary in WhatsNewCard.data()["lines"]:
		assert_bool(UiIcons.has(str(line["icon"]))).is_true()


func test_the_interface_size_snaps_to_its_options_and_scales_the_root() -> void:
	var s := GameSettings.new()
	s._assign("ui_scale", 1.3)
	assert_float(s.ui_scale).is_equal(1.25)
	s._assign("ui_scale", 9.0)
	assert_float(s.ui_scale).is_equal(2.0)
	var before := get_tree().root.content_scale_factor
	s.apply_ui_scale(get_tree())
	assert_float(get_tree().root.content_scale_factor).is_equal(2.0)
	get_tree().root.content_scale_factor = before


func test_the_settings_screen_offers_the_interface_size() -> void:
	var screen := SettingsScreen.open_overlay(self, GameSettings.new())
	await get_tree().process_frame
	assert_int(screen.scale_option.item_count).is_equal((FeelData.settings()["ui_scale_options"] as Array).size())
	screen.close()


func test_each_act_has_its_tint_and_emblem() -> void:
	for act in 3:
		assert_bool(UiIcons.has(UiStyle.act_emblem(act))).is_true()
		assert_object(UiStyle.act_tinted(Color.BLACK, act)).is_not_equal(Color.BLACK)
	assert_object(UiStyle.act_tint(0)).is_not_equal(UiStyle.act_tint(1))
