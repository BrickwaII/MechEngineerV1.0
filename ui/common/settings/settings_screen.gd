class_name SettingsScreen
extends Control
## The settings screen: music, effects and interface volume, screen shake
## on/off and strength, reduced motion, animation speed (1x, 1.5x, 2x or
## skip), fullscreen and interface size. Every change applies and saves at
## once (user://settings.cfg).
##
## Open it from anywhere with the open_settings action (F10), or from code:
##     SettingsScreen.open_overlay(get_tree().root)
## Esc or Close shuts it.

signal closed

const SCENE_PATH := "res://ui/common/settings/settings_screen.tscn"
const OVERLAY_LAYER := 100
const SPEED_LABELS := {"1x": "1x", "1.5x": "1.5x", "2x": "2x", "skip": "Skip"}

## Set before the screen enters the tree; defaults to GameSettings.shared().
var settings: GameSettings

var sliders := {}
var value_labels := {}
var shake_toggle: CheckBox
var reduced_toggle: CheckBox
var fullscreen_toggle: CheckBox
var speed_option: OptionButton
var scale_option: OptionButton
var close_button: Button
var reset_button: Button

var _refreshing := false


## Opens the screen above everything else, under `host` (usually the tree root).
## Returns the open screen; a second call while one is open returns that one.
static func open_overlay(host: Node, p_settings: GameSettings = null) -> SettingsScreen:
	var existing := host.get_node_or_null("SettingsOverlay")
	if existing:
		return existing.get_child(0)
	var layer := CanvasLayer.new()
	layer.name = "SettingsOverlay"
	layer.layer = OVERLAY_LAYER
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var screen: SettingsScreen = load(SCENE_PATH).instantiate()
	screen.settings = p_settings
	screen.closed.connect(layer.queue_free)
	layer.add_child(screen)
	host.add_child(layer)
	return screen


static func is_open(host: Node) -> bool:
	return host.get_node_or_null("SettingsOverlay") != null


func _ready() -> void:
	if settings == null:
		settings = GameSettings.shared()
	theme = PixelTheme.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	_refresh()
	get_tree().root.size_changed.connect(_refresh)
	close_button.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func close() -> void:
	SoundPlayer.fire(&"ui_back")
	closed.emit()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(FeelData.color("background"), 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := Label.new()
	title.text = "Settings"
	title.theme_type_variation = "TitleLabel"
	box.add_child(title)
	box.add_child(HSeparator.new())

	box.add_child(_section("Sound"))
	var grid := _grid(box)
	_slider_row(grid, "music_volume", "Music")
	_slider_row(grid, "effects_volume", "Effects")
	_slider_row(grid, "interface_volume", "Interface")

	box.add_child(_section("Motion"))
	grid = _grid(box)
	shake_toggle = _toggle_row(grid, "shake_enabled", "Screen shake")
	_slider_row(grid, "shake_strength", "Shake strength")
	reduced_toggle = _toggle_row(grid, "reduced_motion", "Reduced motion")
	grid.add_child(_label("Animation speed"))
	speed_option = OptionButton.new()
	var options: Array = FeelData.settings().get("animation_speed_options", SPEED_LABELS.keys())
	for i in options.size():
		speed_option.add_item(SPEED_LABELS.get(options[i], str(options[i])), i)
		speed_option.set_item_metadata(i, options[i])
	speed_option.item_selected.connect(func(index: int) -> void:
		_change("animation_speed", speed_option.get_item_metadata(index)))
	grid.add_child(speed_option)
	grid.add_child(Control.new())

	box.add_child(_section("Display"))
	grid = _grid(box)
	fullscreen_toggle = _toggle_row(grid, "fullscreen", "Fullscreen")
	fullscreen_toggle.name = "FullscreenToggle"
	grid.add_child(_label("Interface size"))
	scale_option = OptionButton.new()
	scale_option.name = "UiScaleOption"
	var scales: Array = FeelData.settings().get("ui_scale_options", [0.0])
	for i in scales.size():
		scale_option.add_item(_scale_text(float(scales[i])), i)
		scale_option.set_item_metadata(i, float(scales[i]))
	scale_option.item_selected.connect(func(index: int) -> void:
		_change("ui_scale", scale_option.get_item_metadata(index)))
	grid.add_child(scale_option)
	grid.add_child(Control.new())

	var hint := Label.new()
	hint.text = "F10 opens this screen anywhere. F11 or Alt+Enter: fullscreen."
	hint.theme_type_variation = "SmallLabel"
	box.add_child(hint)
	box.add_child(HSeparator.new())
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	reset_button = Button.new()
	reset_button.text = "Defaults"
	reset_button.pressed.connect(func() -> void:
		settings.reset_to_defaults()
		settings.save()
		SoundPlayer.fire(&"ui_click")
		_refresh())
	buttons.add_child(reset_button)
	close_button = Button.new()
	close_button.text = "Close"
	close_button.theme_type_variation = "AccentButton"
	close_button.pressed.connect(close)
	buttons.add_child(close_button)


func _section(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = "DimLabel"
	return label


func _grid(parent: Node) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 8)
	parent.add_child(grid)
	return grid


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(200, 0)
	return label


func _slider_row(grid: GridContainer, key: String, text: String) -> void:
	grid.add_child(_label(text))
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = float(FeelData.settings().get("volume_step", 0.05))
	slider.custom_minimum_size = Vector2(220, 20)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(func(v: float) -> void: _change(key, v))
	grid.add_child(slider)
	var value := Label.new()
	value.custom_minimum_size = Vector2(60, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(value)
	sliders[key] = slider
	value_labels[key] = value


func _toggle_row(grid: GridContainer, key: String, text: String) -> CheckBox:
	grid.add_child(_label(text))
	var toggle := CheckBox.new()
	toggle.toggled.connect(func(on: bool) -> void: _change(key, on))
	grid.add_child(toggle)
	grid.add_child(Control.new())
	return toggle



func _change(key: String, value: Variant) -> void:
	if _refreshing:
		return
	settings.set_value(key, value)
	SoundPlayer.fire(&"ui_click")
	_refresh()


## Shows the current settings on every control without re-saving them.
func _refresh() -> void:
	_refreshing = true
	for key: String in sliders:
		sliders[key].value = settings.get(key)
		value_labels[key].text = "%d%%" % roundi(settings.get(key) * 100.0)
	shake_toggle.button_pressed = settings.shake_enabled
	reduced_toggle.button_pressed = settings.reduced_motion
	fullscreen_toggle.button_pressed = settings.fullscreen
	var shake_on := settings.shake_enabled and not settings.reduced_motion
	sliders["shake_strength"].editable = shake_on
	sliders["shake_strength"].modulate.a = 1.0 if shake_on else 0.4
	for i in speed_option.item_count:
		if speed_option.get_item_metadata(i) == settings.animation_speed:
			speed_option.select(i)
	# Sizes too big for this window are greyed out; Auto names the size it picked.
	var window := _window_size()
	for i in scale_option.item_count:
		var size := float(scale_option.get_item_metadata(i))
		scale_option.set_item_disabled(i, not WindowFit.fits(window, size))
		if size <= 0.0:
			scale_option.set_item_text(i, "Auto (%s)" % _scale_text(WindowFit.scale_for(window)))
		if is_equal_approx(size, settings.ui_scale):
			scale_option.select(i)
	_refreshing = false


## "Auto" for 0, else the percent: "150%".
func _scale_text(size: float) -> String:
	return "Auto" if size <= 0.0 else "%d%%" % roundi(size * 100.0)


func _window_size() -> Vector2:
	var window := get_tree().root if is_inside_tree() else null
	return Vector2(window.size) if window != null else WindowFit.min_size()
