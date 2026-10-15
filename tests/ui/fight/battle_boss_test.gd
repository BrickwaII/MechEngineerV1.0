extends GdUnitTestSuite
## A boss fight on the battle screen: the boss is drawn larger in a row of
## its own above its escorts, a wide HP bar names it under the header, the
## header reads "BOSS - <name>", and the bar follows the boss's hp.

const BATTLE_SCENE := preload("res://ui/fight/battle_screen.tscn")
const Helpers := preload("res://tests/ui/fight/fight_ui_helpers.gd")
const BOSS := "precinct_overseer"
const UnitView := preload("res://ui/fight/unit_view.gd")


func _screen() -> BattleScreen:
	var ids: Array[String] = [BOSS, "resistance_soldier_advanced", "resistance_mech_advanced"]
	var table := FixedEnemyTable.from_table(EnemyTable.load_default(), ids)
	var screen: BattleScreen = BATTLE_SCENE.instantiate()
	var request := FightRequest.new(FightRequest.Kind.ATTACK, Campaign.BOSS_ID, 5, StubSquadProvider.new().get_squad())
	screen.setup(request, 7, Helpers.fast_tuning(), null, table)
	var runner := scene_runner(auto_free(screen))
	await runner.simulate_frames(3)
	return screen


func _boss_id(screen: BattleScreen) -> String:
	for c in screen.fight.combatants:
		if BattleArt.base_id(c.id) == BOSS:
			return c.id
	return ""


func test_the_boss_reads_as_a_boss() -> void:
	var screen := await _screen()
	var boss := _boss_id(screen)
	assert_str(boss).is_not_empty()
	screen.show_boss(boss, "Precinct Overseer")
	await get_tree().process_frame
	assert_str(screen.boss_id).is_equal(boss)
	assert_str(screen.header_label.text).is_equal("BOSS  -  PRECINCT OVERSEER")
	# Larger, on its own row above the escorts.
	var panel = screen.unit_panels[boss]
	assert_float(panel.view.size_factor).is_equal(BattleScreen.BOSS_SIZE)
	assert_float(panel.view.custom_minimum_size.x).is_greater(UnitView.STAGE_SIZE.x * 1.5)
	assert_str(panel.get_parent().name).is_equal("BossRow")
	var escort = screen.unit_panels[screen.fight.combatants.filter(func(c: Combatant) -> bool:
		return c.side == Combatant.Side.ENEMY and c.id != boss)[0].id]
	assert_float(panel.global_position.y).is_less(escort.global_position.y)
	assert_float(panel.size.x).is_greater(escort.size.x)
	# The wide bar in the header, beside the boss's name, shows its hp.
	assert_object(screen.boss_bar).is_not_null()
	assert_object(screen.boss_bar.get_parent().get_parent()).is_same(screen.header_label.get_parent())
	var unit := screen.fight.combatant(boss)
	assert_str(screen.boss_bar.caption).is_equal("HP %d/%d" % [unit.hp, unit.max_hp])
	assert_float(screen.boss_bar.size.x).is_greater(600.0)


func test_the_boss_bar_follows_the_boss_hp() -> void:
	var screen := await _screen()
	var boss := _boss_id(screen)
	screen.show_boss(boss, "Precinct Overseer")
	var unit := screen.fight.combatant(boss)
	unit.hp -= 20
	screen.refresh()
	assert_float(screen.boss_bar.max_value).is_equal(float(unit.max_hp))
	assert_str(screen.boss_bar.caption).is_equal("HP %d/%d" % [screen.presenter.shown_hp(boss, unit.hp), unit.max_hp])


func test_showcase_bosses_never_appear_in_a_run() -> void:
	var table := EnemyTable.load_default()
	var bosses := table.enemies.keys().filter(func(id: String) -> bool: return bool(table.enemies[id].get("boss", false)))
	assert_array(bosses).contains(["precinct_overseer", "continental_defense_grid", "last_command"])
	for level: int in table.levels:
		for id: String in bosses:
			assert_array(table.levels[level].pool).not_contains([id])
	var factions: Dictionary = JsonFile.read("res://data/combat/factions.json").factions
	for f: String in factions:
		for unit: Dictionary in factions[f].units:
			for id: String in bosses:
				assert_bool(id.begins_with(str(unit.unit))).is_false()
	assert_array(table.validate(CombatTuning.load_default())).is_empty()
