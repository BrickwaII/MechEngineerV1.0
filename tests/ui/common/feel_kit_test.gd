extends GdUnitTestSuite
## The feel kit: ghost bar, screen shake, number popups, hit pause, tweens.

var settings: GameSettings


func before_test() -> void:
	settings = GameSettings.new()


func _bar(kind := "hp") -> GhostBar:
	var bar: GhostBar = auto_free(GhostBar.new())
	bar.settings = settings
	bar.kind = kind
	bar.reset(100, 100)
	return bar


func test_a_loss_drops_the_fill_and_the_ghost_trails_then_drains() -> void:
	var bar := _bar()
	bar.set_value(60)
	assert_float(bar.shown).is_equal(60.0)
	assert_float(bar.ghost).is_equal(100.0)
	assert_bool(bar.is_flashing()).is_true()
	bar.advance(FeelData.number("ghost_bar.hold_ms") / 1000.0 * 0.9)
	assert_float(bar.ghost).is_equal(100.0)
	for i in 100:
		bar.advance(0.02)
	assert_float(bar.ghost).is_equal(60.0)
	assert_bool(bar.is_animating()).is_false()


func test_a_gain_moves_the_ghost_first_and_the_fill_grows_into_it() -> void:
	var bar := _bar("energy")
	bar.reset(20, 100)
	bar.set_value(50)
	assert_float(bar.ghost).is_equal(50.0)
	assert_float(bar.shown).is_equal(20.0)
	bar.advance(0.05)
	assert_float(bar.shown).is_between(20.01, 49.99)
	bar.advance(1.0)
	assert_float(bar.shown).is_equal(50.0)


func test_skipping_animations_jumps_the_bar() -> void:
	settings.animation_speed = "skip"
	var bar := _bar()
	bar.set_value(30)
	assert_float(bar.ghost).is_equal(30.0)
	assert_bool(bar.is_animating()).is_false()


func test_low_health_changes_color_and_is_flagged_for_stripes() -> void:
	var bar := _bar()
	assert_bool(bar.is_low()).is_false()
	bar.reset(10)
	assert_bool(bar.is_low()).is_true()
	assert_object(bar.fill_color()).is_equal(FeelData.color("hp_low"))
	var energy := _bar("energy")
	energy.reset(5)
	assert_bool(energy.is_low()).is_false()


func test_shake_moves_the_target_and_puts_it_back() -> void:
	var target: Node2D = auto_free(Node2D.new())
	target.position = Vector2(10, 20)
	var shake: ScreenShake = auto_free(ScreenShake.new(target, settings))
	assert_float(shake.shake("big")).is_equal(FeelData.number("shake.big.amplitude_px"))
	var moved := false
	for i in 40:
		shake.advance(0.01)
		moved = moved or target.position != Vector2(10, 20)
		assert_float(absf(target.position.x - 10)).is_less_equal(FeelData.number("shake.big.amplitude_px"))
	assert_bool(moved).is_true()
	assert_object(target.position).is_equal(Vector2(10, 20))


func test_shaking_an_anchored_control_keeps_it_anchored() -> void:
	var parent: Control = auto_free(Control.new())
	add_child(parent)
	parent.size = Vector2(400, 300)
	var target := Control.new()
	parent.add_child(target)
	target.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	target.offset_bottom = -8
	var shake: ScreenShake = auto_free(ScreenShake.new(target, settings))
	shake.shake("big")
	for i in 40:
		shake.advance(0.01)
	assert_float(target.offset_bottom).is_equal(-8.0)
	# It still follows its parent's size, as a screen must on a resize.
	parent.size = Vector2(400, 200)
	assert_float(target.size.y).is_equal(192.0)


func test_no_shake_when_off_or_reduced_motion() -> void:
	var target: Node2D = auto_free(Node2D.new())
	var shake: ScreenShake = auto_free(ScreenShake.new(target, settings))
	settings.shake_enabled = false
	assert_float(shake.shake("big")).is_equal(0.0)
	settings.shake_enabled = true
	settings.reduced_motion = true
	assert_float(shake.shake("big")).is_equal(0.0)
	assert_bool(shake.is_shaking()).is_false()


func test_shake_strength_scales_the_amplitude() -> void:
	settings.shake_strength = 0.5
	var shake: ScreenShake = auto_free(ScreenShake.new(auto_free(Node2D.new()), settings))
	assert_float(shake.shake("big")).is_equal(FeelData.number("shake.big.amplitude_px") * 0.5)


func test_shake_offsets_are_whole_pixels_and_end_at_zero() -> void:
	for i in 20:
		var offset := ScreenShake.offset_at(i * 0.01, 0.2, 5.0, 24.0)
		assert_float(offset.x).is_equal(roundf(offset.x))
	assert_object(ScreenShake.offset_at(0.2, 0.2, 5.0, 24.0)).is_equal(Vector2.ZERO)


func test_popups_show_kind_by_sign_and_icon_not_only_color() -> void:
	assert_str(NumberPopup.text_for(12, "damage")).is_equal("-12")
	assert_str(NumberPopup.text_for(30, "crit")).is_equal("-30!")
	assert_str(NumberPopup.text_for(8, "heal")).is_equal("+8")
	assert_str(NumberPopup.text_for(3, "energy")).is_equal("+3 EN")
	assert_str(NumberPopup.text_for(-3, "energy")).is_equal("-3 EN")
	assert_object(NumberPopup.icon_for("heal")).is_not_null()
	assert_object(NumberPopup.icon_for("energy")).is_not_null()
	assert_object(NumberPopup.icon_for("damage")).is_null()


func test_a_popup_frees_itself_after_its_lifetime() -> void:
	settings.animation_speed = "2x"
	var parent: Node2D = auto_free(Node2D.new())
	add_child(parent)
	var popup := NumberPopup.spawn(parent, Vector2(50, 50), 7, "heal", settings)
	assert_float(popup.lifetime()).is_greater(0.0)
	await await_millis(int(popup.lifetime() * 1000) + 150)
	assert_bool(is_instance_valid(popup)).is_false()


func test_hit_pause_freezes_game_time_then_restores_it() -> void:
	var ms := HitPause.trigger(get_tree(), "light", settings)
	assert_int(ms).is_equal(int(FeelData.number("hit_pause.light_ms")))
	assert_float(Engine.time_scale).is_equal(FeelData.number("hit_pause.time_scale"))
	assert_bool(HitPause.is_active()).is_true()
	await HitPause.finished(get_tree())
	assert_float(Engine.time_scale).is_equal(1.0)


func test_hit_pause_is_skipped_with_animations() -> void:
	settings.animation_speed = "skip"
	assert_int(HitPause.trigger(get_tree(), "heavy", settings)).is_equal(0)
	assert_float(Engine.time_scale).is_equal(1.0)


func test_tween_durations_follow_animation_speed() -> void:
	var base := float(FeelTween.preset("ui")["ms"]) / 1000.0
	assert_float(FeelTween.seconds("ui", settings)).is_equal_approx(base, 0.0001)
	settings.animation_speed = "2x"
	assert_float(FeelTween.seconds("ui", settings)).is_equal_approx(base / 2.0, 0.0001)


func test_reduced_motion_drops_overshoot() -> void:
	assert_int(FeelTween.transition("ui_pop", settings)).is_equal(Tween.TRANS_BACK)
	settings.reduced_motion = true
	assert_int(FeelTween.transition("ui_pop", settings)).is_equal(Tween.TRANS_QUAD)


func test_a_preset_tween_reaches_its_value() -> void:
	var node: Node2D = auto_free(Node2D.new())
	add_child(node)
	var tween := FeelTween.to(node, "position:x", 40.0, "ui_fast", settings)
	await tween.finished
	assert_float(node.position.x).is_equal(40.0)
