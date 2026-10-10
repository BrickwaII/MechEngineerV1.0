extends RefCounted
## Button styles shared by the fight and draft screens, so enabled, disabled
## and selected buttons read apart at a glance.

const Palette := preload("res://ui/fight/fight_palette.gd")


static func make() -> Theme:
	var theme := Theme.new()
	theme.set_stylebox("normal", "Button", _box(Palette.PANEL_RAISED, Palette.TEXT_DIM))
	theme.set_stylebox("hover", "Button", _box(Palette.PANEL_RAISED.lightened(0.08), Palette.TEXT))
	theme.set_stylebox("pressed", "Button", _box(Palette.ACTIVE.darkened(0.55), Palette.ACTIVE))
	theme.set_stylebox("hover_pressed", "Button", _box(Palette.ACTIVE.darkened(0.5), Palette.ACTIVE))
	theme.set_stylebox("disabled", "Button", _box(Palette.BACKGROUND, Palette.RULE))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_color("font_color", "Button", Palette.TEXT)
	theme.set_color("font_hover_color", "Button", Palette.TEXT_BRIGHT)
	theme.set_color("font_pressed_color", "Button", Palette.TEXT_BRIGHT)
	theme.set_color("font_hover_pressed_color", "Button", Palette.TEXT_BRIGHT)
	theme.set_color("font_disabled_color", "Button", Palette.DOWN.lightened(0.2))
	return theme


static func _box(bg: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(4)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	return box
