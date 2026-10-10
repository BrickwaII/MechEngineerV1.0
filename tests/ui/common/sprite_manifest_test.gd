extends GdUnitTestSuite
## The sprite manifest and the sample units in it.


func test_every_sheet_exists_and_fits_the_layout() -> void:
	for id: String in SpriteManifest.unit_ids():
		var size := SpriteManifest.frame_size(id)
		var layout := SpriteManifest.animations(id)
		var cols := 0
		var rows := 0
		for anim: String in layout:
			cols = maxi(cols, int(layout[anim]["frames"]))
			rows = maxi(rows, int(layout[anim]["row"]) + 1)
		for sheet in SpriteManifest.sheets(id):
			assert_bool(ResourceLoader.exists(sheet)).override_failure_message(sheet).is_true()
			var texture: Texture2D = load(sheet)
			assert_int(texture.get_width()).override_failure_message(sheet).is_greater_equal(cols * size.x)
			assert_int(texture.get_height()).override_failure_message(sheet).is_greater_equal(rows * size.y)


func test_the_layout_has_every_animation_the_battle_needs() -> void:
	for anim: String in SpriteManifest.ANIMATIONS:
		assert_bool(SpriteManifest.animations().has(anim)).override_failure_message(anim).is_true()


func test_one_ally_and_one_enemy_sample_in_all_three_tiers() -> void:
	assert_array(SpriteManifest.tiers()).is_equal(["beginner", "medium", "advanced"])
	var kinds := {}
	for id: String in SpriteManifest.unit_ids():
		var unit := SpriteManifest.unit(id)
		kinds[unit["kind"]] = id
		for tier: String in SpriteManifest.tiers():
			if unit["kind"] == "enemy":
				assert_str(SpriteManifest.sheet_for(id, tier)).is_not_empty()
			else:
				for layer: String in unit["layers"]:
					for variant: String in unit["parts"][layer]:
						assert_str(SpriteManifest.sheet_for(id, tier, layer, variant)).is_not_empty()
	assert_bool(kinds.has("ally")).is_true()
	assert_bool(kinds.has("enemy")).is_true()


func test_an_ally_look_is_fixed_by_its_seed() -> void:
	var a := SpriteManifest.ally_look("ally_frame", 42)
	assert_dict(a).is_equal(SpriteManifest.ally_look("ally_frame", 42))
	assert_array(a["parts"].keys()).contains_exactly_in_any_order(["legs", "body", "head", "arm"])
	var looks := {}
	for look_seed in 30:
		looks[str(SpriteManifest.ally_look("ally_frame", look_seed))] = true
	assert_int(looks.size()).is_greater(10)
	assert_dict(SpriteManifest.ally_look("enemy_drone", 1)).is_empty()


func test_every_ally_palette_covers_every_key_color() -> void:
	var keys := SpriteManifest.key_colors()
	assert_int(keys.size()).is_equal(7)
	for name: String in SpriteManifest.data()["ally_palettes"]:
		assert_int(SpriteManifest.palette_colors(name).size()).is_equal(keys.size())
		assert_bool(Color.MAGENTA in SpriteManifest.palette_colors(name)).override_failure_message(name).is_false()


func test_sprite_frames_follow_the_layout() -> void:
	var sheet := SpriteManifest.sheet_for("enemy_drone", "medium")
	var frames := SpriteManifest.sprite_frames(sheet, "enemy_drone")
	for anim: String in SpriteManifest.animations():
		var spec: Dictionary = SpriteManifest.animations()[anim]
		assert_int(frames.get_frame_count(anim)).is_equal(int(spec["frames"]))
		assert_bool(frames.get_animation_loop(anim)).is_equal(spec["loop"])


func test_a_unit_sprite_stacks_ally_layers_and_plays_animations() -> void:
	var sprite: UnitSprite = auto_free(UnitSprite.new())
	sprite.settings = GameSettings.new()
	sprite.setup("ally_frame", "advanced", SpriteManifest.ally_look("ally_frame", 3))
	assert_int(sprite.layer_count()).is_equal(4)
	sprite.play("attack")
	assert_str(String(sprite.current_animation())).is_equal("attack")
	var enemy: UnitSprite = auto_free(UnitSprite.new())
	enemy.setup("enemy_drone", "beginner")
	assert_int(enemy.layer_count()).is_equal(1)


func test_skipping_jumps_to_the_last_frame() -> void:
	var sprite: UnitSprite = auto_free(UnitSprite.new())
	sprite.settings = GameSettings.new()
	sprite.settings.animation_speed = "skip"
	sprite.setup("enemy_drone", "beginner")
	sprite.play("down")
	assert_int(sprite.current_frame()).is_equal(int(SpriteManifest.animations()["down"]["frames"]) - 1)


func test_every_effect_sheet_exists() -> void:
	for name: String in SpriteManifest.data()["effects"]:
		var frames := SpriteManifest.effect_frames(name)
		assert_object(frames).is_not_null()
		assert_int(frames.get_frame_count(name)).is_equal(int(SpriteManifest.data()["effects"][name]["frames"]))
