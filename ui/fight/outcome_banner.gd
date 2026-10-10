extends Control
## The victory or defeat moment: the battlefield dims, the word pops in with
## its stinger, the winners strike a pose, and after a short hold (or a click)
## the screen hands off to the post-fight readout. Timing and colors in
## data/ui/battle_presentation.json "outcome"; the pop is feel tween "ui_pop".
## With the skip animation setting (or headless) it finishes at once.

signal finished

var settings: GameSettings
var headless := DisplayServer.get_name() == "headless"
var victory := false
var shade: ColorRect
var word: Label
var sub: Label

var _done := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


## Plays the moment. `poses` are the UnitViews of the side that won, which
## celebrate (a heal flourish) while the word holds.
func play(p_victory: bool, poses: Array = []) -> void:
	victory = p_victory
	_done = false
	var outcome: Dictionary = BattleArt.data().get("outcome", {})
	var s := settings if settings else GameSettings.shared()
	SoundPlayer.fire(StringName(outcome.get("victory_sound" if victory else "defeat_sound", "")))
	if headless or s.skips_animations():
		_finish()
		return
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = true
	shade = ColorRect.new()
	shade.color = Color(FeelData.color("background"), 0.0)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	word = Label.new()
	word.name = "OutcomeWord"
	word.text = "VICTORY" if victory else "DEFEAT"
	word.theme_type_variation = &"TitleLabel"
	word.add_theme_font_size_override("font_size", PixelTheme.font_size("title") * 2)
	word.add_theme_color_override("font_color", FeelData.color(str(outcome.get("victory_color" if victory else "defeat_color", "text_bright"))))
	word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	word.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(word)
	sub = Label.new()
	sub.text = "the sector is ours" if victory else "the squad falls back"
	sub.theme_type_variation = &"DimLabel"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(sub)
	FeelTween.to(shade, "color:a", float(outcome.get("dim_alpha", 0.55)), "ui_slow", s)
	word.pivot_offset = word.get_combined_minimum_size() / 2.0
	word.scale = Vector2.ONE * (1.0 if s.reduced_motion else 1.6)
	word.modulate.a = 0.0
	FeelTween.to(word, "scale", Vector2.ONE, "ui_pop", s)
	FeelTween.to(word, "modulate:a", 1.0, "ui_fast", s)
	sub.modulate.a = 0.0
	var later := sub.create_tween()
	later.tween_interval(FeelTween.seconds("ui_pop", s))
	later.tween_property(sub, "modulate:a", 1.0, FeelTween.seconds("ui", s))
	for v: Variant in poses:
		if is_instance_valid(v):
			v.set_still(false)
			v.play(&"heal")
	var hold := s.scale_seconds(float(outcome.get("hold_ms", 1400)) / 1000.0)
	get_tree().create_timer(hold).timeout.connect(_finish)


func is_done() -> bool:
	return _done


func _gui_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.pressed:
		accept_event()
		_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	finished.emit()
