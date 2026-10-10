extends Control
## Shows every themed control, the pixel font and the status icons, so the
## theme can be checked for blurry pixels in one place.

const STATUS := [
	["guard", "Guard"], ["charging", "Charging"], ["waiting", "Waiting"],
	["low_energy", "Low energy"], ["down", "Down"], ["intent_changed", "Intent changed"],
]


func _ready() -> void:
	theme = PixelTheme.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var back := ColorRect.new()
	back.color = FeelData.color("background")
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 32)
	margin.add_child(columns)

	var left := _column(columns)
	_add(left, _label("Theme demo", "TitleLabel"))
	_add(left, _label("Mech Pixel 5x7, drawn at 2x. Every pixel square.", ""))
	_add(left, _label("ABCDEFGHIJKLMNOPQRSTUVWXYZ", ""))
	_add(left, _label("abcdefghijklmnopqrstuvwxyz 0123456789", ""))
	_add(left, _label("!?.,:;+-*/=%()[]<>#@&'\"_", "DimLabel"))
	_add(left, _label("Small labels use the 1x size for fine print.", "SmallLabel"))
	_add(left, HSeparator.new())
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	for spec in [["Attack", ""], ["Confirm", "AccentButton"], ["Locked", ""]]:
		var b := Button.new()
		b.text = spec[0]
		b.theme_type_variation = spec[1]
		b.disabled = spec[0] == "Locked"
		b.pressed.connect(func() -> void: SoundPlayer.fire(&"ui_confirm"))
		b.mouse_entered.connect(func() -> void: SoundPlayer.fire(&"ui_hover"))
		buttons.add_child(b)
	_add(left, buttons)
	var check := CheckBox.new()
	check.text = "Screen shake"
	check.button_pressed = true
	_add(left, check)
	var check_off := CheckBox.new()
	check_off.text = "Reduced motion"
	_add(left, check_off)
	var slider := HSlider.new()
	slider.value = 70
	slider.custom_minimum_size = Vector2(260, 20)
	_add(left, slider)
	var option := OptionButton.new()
	for text in ["1x", "1.5x", "2x", "Skip"]:
		option.add_item(text)
	_add(left, option)
	var field := LineEdit.new()
	field.text = "Bot name"
	field.custom_minimum_size = Vector2(260, 0)
	_add(left, field)
	var progress := ProgressBar.new()
	progress.value = 40
	progress.show_percentage = false
	progress.custom_minimum_size = Vector2(260, 16)
	_add(left, progress)

	var right := _column(columns)
	var panel := PanelContainer.new()
	right.add_child(panel)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 10)
	panel.add_child(inner)
	_add(inner, _label("Status icons", "DimLabel"))
	_add(inner, _label("Shape and color together:", "SmallLabel"))
	for spec in STATUS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var icon := TextureRect.new()
		icon.texture = load("res://assets/ui/icons/status_%s.png" % spec[0])
		icon.custom_minimum_size = Vector2(24, 24)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
		row.add_child(_label(spec[1], ""))
		inner.add_child(row)
	_add(inner, HSeparator.new())
	_add(inner, _label("Meters", "DimLabel"))
	for spec in [["hp", 72.0, "HP 72/100"], ["hp", 22.0, "HP 22/100"], ["energy", 55.0, "EN 55/100"]]:
		var bar := GhostBar.new()
		bar.kind = spec[0]
		bar.label = spec[2]
		bar.custom_minimum_size = Vector2(260, 14)
		bar.reset(spec[1], 100.0)
		inner.add_child(bar)
	_add(inner, HSeparator.new())
	_add(inner, _label("Palette", "DimLabel"))
	var swatches := GridContainer.new()
	swatches.columns = 8
	for name in ["background", "panel", "panel_raised", "accent", "warning", "danger", "ally", "enemy",
			"active", "selected", "changed", "preview", "hp", "energy", "hp_ghost", "text"]:
		var swatch := ColorRect.new()
		swatch.color = FeelData.color(name)
		swatch.custom_minimum_size = Vector2(28, 28)
		swatch.tooltip_text = name
		swatches.add_child(swatch)
	_add(inner, swatches)


func _column(parent: Node) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	parent.add_child(box)
	return box


func _label(text: String, variation: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	return label


func _add(parent: Node, child: Control) -> void:
	if not child is HSeparator:
		child.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	parent.add_child(child)
