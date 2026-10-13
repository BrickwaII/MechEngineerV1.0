extends GdUnitTestSuite
## Unit names on the battle screen are never clipped and never shrink: a long
## name wraps at the body size; the full name is in its tooltip.

const BATTLE_SCENE := preload("res://ui/fight/battle_screen.tscn")
const Helpers := preload("res://tests/ui/fight/fight_ui_helpers.gd")


## The longest enemy names in the shipped table, plus every demo boss lineup.
func _lineups() -> Array:
	var table := EnemyTable.load_default()
	var ids: Array = table.enemies.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return table.name_of(a).length() > table.name_of(b).length())
	var out := [ids.slice(0, 5)]
	for s in DemoScenario.load_all():
		if s.is_fight() and not (s.fight.get("enemies", []) as Array).is_empty():
			out.append(s.fight.enemies)
	return out


func test_no_unit_name_is_clipped() -> void:
	var base := EnemyTable.load_default()
	for lineup: Array in _lineups():
		var ids: Array[String] = []
		ids.assign(lineup)
		var table := FixedEnemyTable.from_table(base, ids)
		var screen: BattleScreen = BATTLE_SCENE.instantiate()
		screen.setup(Helpers.request(5), 7, Helpers.fast_tuning(), null, table)
		var runner := scene_runner(auto_free(screen))
		await runner.simulate_frames(4)
		for id: String in screen.unit_panels:
			var panel = screen.unit_panels[id]
			assert_bool(panel.name_fits()).override_failure_message("%s does not fit" % panel.name_label.text).is_true()
			assert_str(panel.name_label.tooltip_text).is_not_empty()
		screen.queue_free()
		await runner.simulate_frames(1)


func test_a_short_name_keeps_the_body_font() -> void:
	var screen := Helpers.screen(1)
	var runner := scene_runner(auto_free(screen))
	await runner.simulate_frames(4)
	for id: String in screen.unit_panels:
		var panel = screen.unit_panels[id]
		if panel.name_label.text.length() <= 8:
			assert_bool(panel.name_label.has_theme_font_size_override("font_size")).is_false()
			assert_int(panel.name_label.autowrap_mode).is_equal(TextServer.AUTOWRAP_OFF)
