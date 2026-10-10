extends Control
## A horizontal bar: a solid fill, an optional hatched ghost segment for a
## pending cost, and optional marker lines. All positions are 0 to 1 of the width.
## It draws no numbers.

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


func _draw() -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(Vector2.ZERO, size), background)
	draw_rect(Rect2(0, 0, w * fill_ratio, h), fill_color)
	if ghost_ratio > 0.0:
		var x0 := w * ghost_from
		var x1 := minf(w, w * (ghost_from + ghost_ratio))
		draw_rect(Rect2(x0, 0, x1 - x0, h), ghost_dark)
		# Diagonal hatch, clipped to the ghost by drawing only inside it.
		var step := 6.0
		var x := x0 - h
		while x < x1:
			var a := Vector2(maxf(x, x0), h - (maxf(x, x0) - x))
			var b := Vector2(minf(x + h, x1), h - (minf(x + h, x1) - x))
			draw_line(a, b, ghost_color, 3.0)
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
