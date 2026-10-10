extends RefCounted
## Small builders shared by the dev screens, which lay themselves out in code.

const Palette := preload("res://ui/dev/dev_palette.gd")


## A dark theme for a whole dev screen.
static func theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 14
	for type in ["Label", "Button", "CheckBox", "LineEdit", "SpinBox", "OptionButton", "ItemList", "TextEdit"]:
		t.set_color("font_color", type, Palette.TEXT)
	t.set_color("font_color", "TextEdit", Palette.TEXT)
	return t


static func background(parent: Control) -> void:
	var bg := ColorRect.new()
	bg.color = Palette.BACKGROUND
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(bg)


static func panel() -> PanelContainer:
	var p := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Palette.PANEL
	style.border_color = Palette.RULE
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(12)
	p.add_theme_stylebox_override("panel", style)
	return p


static func label(text: String, color := Palette.TEXT, size := 14) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	return l


static func heading(text: String) -> Label:
	return label(text, Palette.ACCENT, 18)


static func spin(min_value: int, max_value: int, value := 0) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = min_value
	s.max_value = max_value
	s.value = value
	s.rounded = true
	s.custom_minimum_size.x = 96
	return s


static func button(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(on_pressed)
	return b


static func row(children: Array) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	for c: Control in children:
		h.add_child(c)
	return h
