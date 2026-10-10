class_name PixelTheme
extends RefCounted
## The shared interface theme: the Mech Pixel font, bevelled pixel boxes from
## assets/ui/ and colors from data/feel/palette.json.
##
## Screens use `theme = PixelTheme.theme()` on their root Control. The theme is
## saved as ui/common/pixel_theme.tres for the editor; after changing the
## palette or this file, rebuild it with
##     godot --headless --path . -s res://ui/common/build_theme.gd
##
## Type variations: TitleLabel, DimLabel, SmallLabel, AccentButton.

const THEME_PATH := "res://ui/common/pixel_theme.tres"
const FONT_PATH := "res://assets/fonts/mech_pixel.fnt"
const UI_DIR := "res://assets/ui/"
## Pixel boxes are 24x24 (12x12 art at 2x); this many pixels on each edge
## stay unstretched.
const SLICE := 8

static var _theme: Theme


static func theme() -> Theme:
	if _theme == null:
		_theme = load(THEME_PATH) if ResourceLoader.exists(THEME_PATH) else build()
	return _theme


static func font() -> Font:
	return load(FONT_PATH)


## "small" 10, "body" 20 or "title" 30: multiples of the font's 10 px.
static func font_size(name := "body") -> int:
	return int(FeelData.feel().get("theme", {}).get("font_sizes", {}).get(name, 20))


static func build() -> Theme:
	var t := Theme.new()
	var body := font_size("body")
	t.default_font = font()
	t.default_font_size = body

	t.set_color("font_color", "Label", FeelData.color("text"))
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.6))
	t.set_constant("shadow_offset_x", "Label", 2)
	t.set_constant("shadow_offset_y", "Label", 2)
	t.set_constant("line_spacing", "Label", 2)
	_variation(t, "TitleLabel", "Label")
	t.set_font_size("font_size", "TitleLabel", font_size("title"))
	t.set_color("font_color", "TitleLabel", FeelData.color("text_bright"))
	_variation(t, "DimLabel", "Label")
	t.set_color("font_color", "DimLabel", FeelData.color("text_dim"))
	_variation(t, "SmallLabel", "Label")
	t.set_font_size("font_size", "SmallLabel", font_size("small"))
	t.set_color("font_color", "SmallLabel", FeelData.color("text_dim"))

	t.set_stylebox("panel", "Panel", _box("panel"))
	t.set_stylebox("panel", "PanelContainer", _box("panel_raised", 20, 16))
	t.set_stylebox("panel", "PopupMenu", _box("panel_raised", 6, 4))
	t.set_stylebox("panel", "TooltipPanel", _box("tooltip", 6, 4))
	t.set_color("font_color", "TooltipLabel", FeelData.color("text"))

	for type in ["Button", "OptionButton", "CheckBox", "CheckButton"]:
		_button_styles(t, type, type in ["Button", "OptionButton"])
		t.set_color("font_color", type, FeelData.color("text"))
		t.set_color("font_hover_color", type, FeelData.color("text_bright"))
		t.set_color("font_pressed_color", type, FeelData.color("accent_hover"))
		t.set_color("font_focus_color", type, FeelData.color("text_bright"))
		t.set_color("font_disabled_color", type, FeelData.color("disabled_text"))
		t.set_constant("h_separation", type, 8)
	_variation(t, "AccentButton", "Button")
	t.set_color("font_color", "AccentButton", FeelData.color("accent_hover"))

	t.set_icon("checked", "CheckBox", _tex("check_on"))
	t.set_icon("unchecked", "CheckBox", _tex("check_off"))
	t.set_icon("checked", "CheckButton", _tex("check_on"))
	t.set_icon("unchecked", "CheckButton", _tex("check_off"))
	t.set_icon("arrow", "OptionButton", _tex("arrow_down"))

	var track := StyleBoxFlat.new()
	track.bg_color = FeelData.color("bar_back")
	track.border_color = FeelData.color("panel_border")
	track.set_border_width_all(1)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	track.anti_aliasing = false
	var filled := track.duplicate() as StyleBoxFlat
	filled.bg_color = FeelData.color("accent_pressed")
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", filled)
	t.set_stylebox("grabber_area_highlight", "HSlider", filled)
	t.set_icon("grabber", "HSlider", _tex("slider_grabber"))
	t.set_icon("grabber_highlight", "HSlider", _tex("slider_grabber_highlight"))

	t.set_stylebox("normal", "LineEdit", _box("field", 6, 4))
	t.set_stylebox("focus", "LineEdit", _box("focus"))
	t.set_color("font_color", "LineEdit", FeelData.color("text"))

	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = FeelData.color("accent")
	bar_fill.anti_aliasing = false
	t.set_stylebox("background", "ProgressBar", _box("field"))
	t.set_stylebox("fill", "ProgressBar", bar_fill)

	var rule := StyleBoxLine.new()
	rule.color = FeelData.color("rule")
	rule.thickness = 2
	t.set_stylebox("separator", "HSeparator", rule)
	t.set_constant("separation", "HSeparator", 8)
	return t


static func _variation(t: Theme, name: String, base: String) -> void:
	t.add_type(name)
	t.set_type_variation(name, base)


static func _button_styles(t: Theme, type: String, boxed: bool) -> void:
	var margins: Array = FeelData.feel().get("theme", {}).get("content_margin_px", [8, 4])
	var h := int(margins[0])
	var v := int(margins[1])
	if boxed:
		t.set_stylebox("normal", type, _box("button_normal", h, v))
		t.set_stylebox("hover", type, _box("button_hover", h, v))
		t.set_stylebox("pressed", type, _box("button_pressed", h, v + 0, 2))
		t.set_stylebox("disabled", type, _box("button_disabled", h, v))
	else:
		var flat := StyleBoxEmpty.new()
		flat.set_content_margin_all(v)
		for state in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
			t.set_stylebox(state, type, flat)
	t.set_stylebox("focus", type, _box("focus"))


## A 9-slice style box from assets/ui/<name>.png. `push_down` moves the content
## down that many pixels (pressed buttons).
static func _box(name: String, h_margin := 0, v_margin := 0, push_down := 0) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = _tex(name)
	box.set_texture_margin_all(SLICE)
	box.content_margin_left = h_margin
	box.content_margin_right = h_margin
	box.content_margin_top = v_margin + push_down
	box.content_margin_bottom = maxi(0, v_margin - push_down)
	return box


static func _tex(name: String) -> Texture2D:
	return load(UI_DIR + name + ".png")
