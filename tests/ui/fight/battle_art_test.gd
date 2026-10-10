extends GdUnitTestSuite
## How units look on the battle screen: ally parts and palettes, tiers, and
## enemy sprites with a fallback.

const Helpers := preload("res://tests/ui/fight/fight_ui_helpers.gd")


func _unit(id: String, side: Combatant.Side) -> Combatant:
	var tuning := CombatTuning.load_default()
	var skills: Array[String] = ["strike"]
	return Combatant.new(id, id, side, 0, UnitStats.new(30, 5, 3, 5, 1, 10), 30, skills, tuning)


func test_allies_have_at_least_four_variants_per_part_and_eight_palettes() -> void:
	var ally := SpriteManifest.unit(str(BattleArt.data().ally_unit))
	for layer: String in ally.layers:
		assert_int(ally.parts[layer].size()).override_failure_message(layer).is_greater_equal(4)
	assert_int(ally.palettes.size()).is_greater_equal(8)
	for palette: String in ally.palettes:
		assert_bool(SpriteManifest.data().ally_palettes.has(palette)).override_failure_message(palette).is_true()


func test_every_drafted_bot_looks_different() -> void:
	var looks := {}
	for i in 20:
		var look := BattleArt.look_for(_unit("bot_%d" % i, Combatant.Side.PLAYER), 1, BattleTierRule.defaults())
		looks[str(look.look)] = true
		assert_dict(look).is_equal(BattleArt.look_for(_unit("bot_%d" % i, Combatant.Side.PLAYER), 1, BattleTierRule.defaults()))
	assert_int(looks.size()).is_greater(15)


func test_an_allys_tier_follows_the_rule() -> void:
	var skills: Array[Skill] = [Skill.new("Strike", "damage_single")]
	var bot := Bot.new("b", "B", UnitStats.new(30, 5, 3, 5, 1, 10), Personality.new(3), skills)
	var unit := _unit("b", Combatant.Side.PLAYER)
	assert_str(BattleArt.look_for(unit, 0, BattleTierRule.defaults(), bot).tier).is_equal("advanced")
	assert_str(BattleArt.look_for(unit, 0, BattleTierRule.defaults()).tier).is_equal("beginner")


func test_enemies_use_their_manifest_entry_or_the_fallback() -> void:
	var drone := BattleArt.look_for(_unit("scrap_drone#1", Combatant.Side.ENEMY), 0, BattleTierRule.defaults())
	assert_str(drone.unit_id).is_equal("enemy_drone")
	var direct := BattleArt.look_for(_unit("enemy_drone#2", Combatant.Side.ENEMY), 0, BattleTierRule.defaults())
	assert_str(direct.unit_id).is_equal("enemy_drone")
	var unknown := BattleArt.look_for(_unit("never_heard_of#1", Combatant.Side.ENEMY), 0, BattleTierRule.defaults())
	assert_str(unknown.unit_id).is_empty()
	assert_bool(ResourceLoader.exists(unknown.sheet)).is_true()
	assert_int(unknown.palette.size()).is_equal(SpriteManifest.key_colors().size())


func test_enemy_tiers_follow_the_defense_level() -> void:
	var tiers: Array = BattleArt.data().enemy_tier_by_defense_level
	assert_int(tiers.size()).is_equal(FightRequest.MAX_DEFENSE_LEVEL + 1)
	for level in tiers.size():
		assert_str(BattleArt.enemy_tier(level)).is_equal(tiers[level])
		assert_array(SpriteManifest.tiers()).contains([tiers[level]])


func test_every_tier_has_a_plate_and_the_glow_grows() -> void:
	var last := -1.0
	for tier: String in SpriteManifest.tiers():
		var look := BattleArt.tier_look(tier)
		assert_bool(ResourceLoader.exists(str(look.plate))).override_failure_message(tier).is_true()
		assert_float(float(look.glow_alpha)).is_greater_equal(last)
		last = float(look.glow_alpha)
	assert_float(last).is_greater(0.0)


func test_every_effect_sheet_cuts_into_frames() -> void:
	for name: String in BattleArt.effect_names():
		var frames := BattleArt.effect_frames(name)
		assert_object(frames).override_failure_message(name).is_not_null()
		assert_int(frames.get_frame_count(name)).is_equal(int(BattleArt.data().effects[name].frames))


func test_every_unit_on_screen_is_an_animated_sprite() -> void:
	var screen: BattleScreen = auto_free(Helpers.screen(4))
	add_child(screen)
	await get_tree().process_frame
	for c in screen.fight.combatants:
		var view = screen.unit_panels[c.id].view
		assert_int(view.sprite.layer_count()).override_failure_message(c.id).is_greater(0)
		for anim: String in SpriteManifest.ANIMATIONS:
			assert_bool(view.sprite._layers[0].sprite_frames.has_animation(anim)).is_true()
