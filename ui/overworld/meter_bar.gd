extends Control
## A horizontal bar: a solid fill, an optional hatched ghost segment for a
## pending cost, and optional marker lines. All positions are 0 to 1 of the width.
## It draws no numbers.
##
## animate_to() shows a change the way the feel kit's GhostBar does: on a loss
## the fill drops at once and a pale trail of the old value holds, then drains
## down to it; on a gain the trail jumps ahead and the fill grows into it. The
## pending ghost's hatch marches and breathes while `fx` is set (the map's
## MapFx clock). Timings: data/feel/screens.json "map".

var fill_ratio := 0.0:
	set(v):
		fill_ratio = clampf(v, 0.0, 1.0)
		queue_redraw()
var fill_color := Color("#f2b84b"):
	set(v):
		fill_color = v
		queue_redraw()
## Where the ghost starts and how wide it is. Width 0 hides it.
var ghost_from := 0.0:
	set(v):
		ghost_from = clampf(v, 0.0, 1.0)
		queue_redraw()
var ghost_ratio := 0.0:
	set(v):
		ghost_ratio = maxf(v, 0.0)
		queue_redraw()
var ghost_color := Color("#ff6b5e")
var ghost_dark := Color("#7a2a26")
## Ratio -> Color for thin vertical markers, such as "now" or "payload".
var markers: Dictionary = {}:
	set(v):
		markers = v
		queue_redraw()
## Pixel spacing of segment gaps across the bar; 0 for a plain bar.
var segment_px := 0.0
var background := Color("#1a2736")
var border := Color("#2c4054")
var gap_color := Color("#0f1824")
## The pale trail behind a change (see animate_to()).
var trail_color := Color("#ffe08a")
## Drives the pending hatch's march and pulse; null keeps it still.
var fx: MapFx
var settings: GameSettings

## Where the fill is heading, and the trail of the last change.
var target_ratio := 0.0
var trail_ratio := 0.0
var _fill_from := 0.0
var _fill_t := -1.0
var _trail_from := 0.0
var _trail_t := -1.0
var _hold_left := 0.0


## Moves the fill to `ratio`, showing the change. The first call, or one with
## animations skipped, sets it at once.
func animate_to(ratio: float, instant := false) -> void:
	ratio = clampf(ratio, 0.0, 1.0)
	if instant or _settings().skips_animations():
		target_ratio = ratio
		fill_ratio = ratio
		trail_ratio = ratio
		_fill_t = -1.0
		_trail_t = -1.0
		return
	if is_equal_approx(ratio, target_ratio):
		return
	if ratio < target_ratio:
		trail_ratio = maxf(trail_ratio, fill_ratio)
		fill_ratio = ratio
		_fill_t = -1.0
		_trail_from = trail_ratio
		_trail_t = -1.0
		_hold_left = ScreenFeel.seconds("map.ghost_hold_ms", _settings())
	else:
		trail_ratio = ratio
		_trail_t = -1.0
		_fill_from = fill_ratio
		_fill_t = 0.0
	target_ratio = ratio
	queue_redraw()


func is_animating() -> bool:
	return not is_equal_approx(fill_ratio, target_ratio) or not is_equal_approx(trail_ratio, target_ratio)


func _process(delta: float) -> void:
	advance(delta)
	if fx != null and ghost_ratio > 0.0:
		queue_redraw()


## Moves the fill and trail forward by `delta` seconds.
func advance(delta: float) -> void:
	if not is_animating():
		# Within float tolerance counts as arrived: land exactly, so an eased
		# trail never stops a hair short of the target.
		fill_ratio = target_ratio
		trail_ratio = target_ratio
		return
	if _fill_t >= 0.0:
		_fill_t += delta
		var fill_s := ScreenFeel.seconds("map.meter_ms", _settings())
		fill_ratio = target_ratio if fill_s <= 0.0 or _fill_t >= fill_s else \
			Tween.interpolate_value(_fill_from, target_ratio - _fill_from, _fill_t, fill_s, Tween.TRANS_QUAD, Tween.EASE_OUT)
		if is_equal_approx(fill_ratio, target_ratio):
			_fill_t = -1.0
	if trail_ratio > target_ratio:
		if _hold_left > 0.0:
			_hold_left -= delta
		else:
			_trail_t = maxf(_trail_t, 0.0) + delta
			var drain_s := ScreenFeel.seconds("map.ghost_drain_ms", _settings())
			trail_ratio = target_ratio if drain_s <= 0.0 or _trail_t >= drain_s else \
				Tween.interpolate_value(_trail_from, target_ratio - _trail_from, _trail_t, drain_s, Tween.TRANS_QUAD, Tween.EASE_IN_OUT)
	elif trail_ratio < target_ratio:
		trail_ratio = target_ratio
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(Vector2.ZERO, size), background)
	if trail_ratio > fill_ratio:
		draw_rect(Rect2(w * fill_ratio, 0, w * (trail_ratio - fill_ratio), h), Color(trail_color, 0.75))
	draw_rect(Rect2(0, 0, w * fill_ratio, h), fill_color)
	if ghost_ratio > 0.0:
		var x0 := w * ghost_from
		var x1 := minf(w, w * (ghost_from + ghost_ratio))
		draw_rect(Rect2(x0, 0, x1 - x0, h), ghost_dark)
		# Diagonal hatch, clipped to the ghost by drawing only inside it. It
		# marches along and breathes so the pending cost catches the eye.
		var step := 6.0
		var march := fmod(fx.pending_march_px(), step) if fx != null else 0.0
		var hatch := Color(ghost_color, fx.pending_pulse()) if fx != null else ghost_color
		var x := x0 - h - step + march
		while x < x1:
			if x + h > x0:
				var a := Vector2(maxf(x, x0), h - (maxf(x, x0) - x))
				var b := Vector2(minf(x + h, x1), h - (minf(x + h, x1) - x))
				draw_line(a, b, hatch, 3.0)
			x += step
	if segment_px > 0.0:
		var sx := segment_px
		while sx < w:
			draw_rect(Rect2(sx - 1.0, 0, 2.0, h), gap_color)
			sx += segment_px
	for ratio: float in markers:
		var mx := clampf(ratio, 0.0, 1.0) * w
		draw_rect(Rect2(mx - 1.0, -3.0, 2.0, h + 6.0), markers[ratio])
	draw_rect(Rect2(Vector2.ZERO, size), border, false, 1.0)


func _settings() -> GameSettings:
	return settings if settings else GameSettings.shared()
