class_name ScreenTheme
extends RefCounted
## P1's PixelTheme for the map, draft, readout and run screens, with one
## addition: glyphs the pixel font lacks (· and ×) fall back to Godot's
## default font instead of drawing as boxes.
##
## The pixel font stays crisp only at whole steps of its 10 px, so size()
## snaps any font size to 10, 20 or 30.

static var _theme: Theme


static func theme() -> Theme:
	if _theme == null:
		_theme = PixelTheme.theme().duplicate()
		_theme.default_font = font()
	return _theme


static func font() -> Font:
	var font := FontVariation.new()
	font.base_font = PixelTheme.font()
	font.fallbacks = [ThemeDB.fallback_font]
	return font


## The pixel step nearest `font_size`: small (10), body (20) or title (30).
static func size(font_size: int) -> int:
	if font_size <= 14:
		return PixelTheme.font_size("small")
	if font_size <= 24:
		return PixelTheme.font_size("body")
	return PixelTheme.font_size("title")
