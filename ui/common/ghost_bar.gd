class_name GhostBar
extends Control
## A meter that shows every change. On a loss the fill drops at once, flashes,
## and a ghost of the old value holds then drains down to it. On a gain the
## ghost jumps ahead to the new value and the fill grows into it. Timings come
## from data/feel/feel.json ("ghost_bar", tweens "meter_drain", "meter_fill").
##
## kind "hp" turns to the low color AND gets dark stripes below
## ghost_bar.low_share, so low health reads without color.

## "hp" or "energy": picks the palette colors.
@export var kind := "hp":
	set(v):
		kind = v
		queue_redraw()
@export var max_value := 100.0
## Text drawn on the bar ("" for none), e.g. "HP".
@export var label := ""

var settings: GameSettings
## What the fill shows right now.
var shown := 100.0
## Where the ghost is right now.
var ghost := 100.0
## The value the bar is heading to.
var value := 100.0

var _fill_from := 0.0
var _fill_t := -1.0
var _ghost_from := 0.0
var _ghost_t := -1.0
var _hold_left := 0.0
var _flash_left := 0.0


func _init() -> void:
	custom_minimum_size = Vector2(80, FeelData.number("ghost_bar.height_px", 10.0))
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Sets the value at once, with no animation (use when a screen first opens).
func reset(p_value: float, p_max: float = -1.0) -> void:
	if p_max > 0.0:
		max_value = p_max
	value = clampf(p_value, 0.0, max_value)
	shown = value
	ghost = value
	_fill_t = -1.0
	_ghost_t = -1.0
	_hold_left = 0.0
	_flash_left = 0.0
	queue_redraw()


## Moves to `p_value`, animating the change.
func set_value(p_value: float) -> void:
	p_value = clampf(p_value, 0.0, max_value)
	if is_equal_approx(p_value, value):
		return
	if _settings().skips_animations():
		reset(p_value)
		return
	if p_value < value:
		ghost = maxf(ghost, shown)
		shown = p_value
		_fill_t = -1.0
		_ghost_from = ghost
		_ghost_t = -1.0
		_hold_left = _settings().scale_seconds(FeelData.number("ghost_bar.hold_ms") / 1000.0)
		_flash_left = _settings().scale_seconds(FeelData.number("ghost_bar.flash_ms") / 1000.0)
	else:
		ghost = p_value
		_ghost_t = -1.0
		_hold_left = 0.0
		_fill_from = shown
		_fill_t = 0.0
	value = p_value
	set_process(true)
	queue_redraw()


func is_animating() -> bool:
	return not is_equal_approx(shown, value) or not is_equal_approx(ghost, value) or _flash_left > 0.0


func is_flashing() -> bool:
	return _flash_left > 0.0


func _process(delta: float) -> void:
	advance(delta)


## Moves the animation forward by `delta` seconds.
func advance(delta: float) -> void:
	_flash_left = maxf(0.0, _flash_left - delta)
	if _fill_t >= 0.0:
		_fill_t += delta
		shown = FeelTween.sample("meter_fill", _fill_from, value, _fill_t, _settings())
		if is_equal_approx(shown, value):
			_fill_t = -1.0
	if ghost > value:
		if _hold_left > 0.0:
			_hold_left -= delta
		else:
			_ghost_t = maxf(_ghost_t, 0.0) + delta
			ghost = FeelTween.sample("meter_drain", _ghost_from, value, _ghost_t, _settings())
	if not is_animating():
		shown = value
		ghost = value
		set_process(false)
	queue_redraw()


func is_low() -> bool:
	return kind == "hp" and value <= max_value * FeelData.number("ghost_bar.low_share", 0.3)


func fill_color() -> Color:
	if kind == "energy":
		return FeelData.color("energy")
	return FeelData.color("hp_low") if is_low() else FeelData.color("hp")


func ghost_color() -> Color:
	return FeelData.color("energy_ghost" if kind == "energy" else "hp_ghost")


func _draw() -> void:
	var border := FeelData.number("ghost_bar.border_px", 1.0)
	var outer := Rect2(Vector2.ZERO, size.floor())
	draw_rect(outer, FeelData.color("panel_border"))
	var inner := outer.grow(-border)
	draw_rect(inner, FeelData.color("bar_back"))
	var ghost_w := floorf(inner.size.x * ghost / max_value)
	var fill_w := floorf(inner.size.x * shown / max_value)
	if ghost_w > fill_w:
		draw_rect(Rect2(inner.position, Vector2(ghost_w, inner.size.y)), ghost_color())
	var fill_rect := Rect2(inner.position, Vector2(fill_w, inner.size.y))
	draw_rect(fill_rect, fill_color())
	if fill_w > 0:
		draw_rect(Rect2(inner.position, Vector2(fill_w, 1)), fill_color().lightened(0.3))
	if is_low():
		_draw_stripes(fill_rect)
	if _flash_left > 0.0:
		draw_rect(inner, Color(FeelData.color("bar_flash"), 0.55))
	if not label.is_empty():
		var font := PixelTheme.font()
		var font_size := 10
		var at := inner.position + Vector2(3, floorf((inner.size.y + font.get_ascent(font_size)) / 2.0) - 1)
		draw_string(font, at + Vector2(1, 1), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)
		draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, FeelData.color("text_bright"))


## Dark diagonal stripes every 4 px over the low part of the fill.
func _draw_stripes(rect: Rect2) -> void:
	var dark := Color(0, 0, 0, 0.35)
	var h := int(rect.size.y)
	var x := int(rect.position.x) - h
	while x < rect.end.x:
		for i in h:
			var px := x + i
			if px >= rect.position.x and px < rect.end.x:
				draw_rect(Rect2(px, rect.position.y + h - 1 - i, 1, 1), dark)
		x += 4


func _settings() -> GameSettings:
	return settings if settings else GameSettings.shared()
