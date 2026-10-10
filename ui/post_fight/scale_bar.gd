extends Control
## One personality scale from -1 to 1: a track, a centre tick, a hollow ring
## where the value was before the fight and a filled dot where it is now.

const TRACK := Color("#2c4054")
const CENTRE := Color("#4a6378")
const BEFORE := Color("#8aa0b4")

var before := 0.0:
	set(v):
		before = clampf(v, -1.0, 1.0)
		queue_redraw()
var after := 0.0:
	set(v):
		after = clampf(v, -1.0, 1.0)
		queue_redraw()
var active := true:
	set(v):
		active = v
		queue_redraw()
var dot_color := Color("#35c2b0")


func _init() -> void:
	custom_minimum_size = Vector2(60, 14)


func _x(value: float) -> float:
	return (value + 1.0) * 0.5 * size.x


func _draw() -> void:
	var mid := size.y * 0.5
	draw_line(Vector2(0, mid), Vector2(size.x, mid), TRACK, 2.0)
	draw_line(Vector2(_x(0.0), mid - 4), Vector2(_x(0.0), mid + 4), CENTRE, 1.0)
	if not active:
		return
	if not is_equal_approx(before, after):
		draw_line(Vector2(_x(before), mid), Vector2(_x(after), mid), dot_color.darkened(0.3), 3.0)
	draw_arc(Vector2(_x(before), mid), 4.5, 0.0, TAU, 16, BEFORE, 1.5)
	draw_circle(Vector2(_x(after), mid), 3.5, dot_color)
