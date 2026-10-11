class_name PersonalityHexagon
extends Control
## A personality as a hexagon: three axes through the centre, one per
## spectrum, with its two ends at opposite corners, so six points, one per end
## (Personality.ENDS). Each point sits as far out as its end's value.
##
## It can animate a growth (only ever outward): `progress` 0 shows the old
## shape; up to outline_share it traces the new shape's outline; then the fill
## grows from the old shape to the new one. Without a growth, set
## `before` = `after` and leave `progress` at 1.

## Corner order around the hexagon, clockwise from the top, as indices into
## Personality.ENDS: each end sits opposite the other end of its spectrum.
const CORNERS: Array[int] = [0, 2, 5, 1, 3, 4]
const GRID := Color("#223244")
const AXIS := Color("#2c4054")
const OLD_FILL := Color("#35c2b0", 0.28)
const NEW_FILL := Color("#35c2b0", 0.55)
const OUTLINE := Color("#7be7d4")
const OLD_LINE := Color("#4f7d84")
const LABEL := Color("#8aa0b4")
const LABEL_GREW := Color("#dbe6f0")

## End values in Personality.ENDS order.
var before: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]:
	set(v):
		before = v
		queue_redraw()
var after: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]:
	set(v):
		after = v
		queue_redraw()
## 0 to 1 through the growth.
var progress := 1.0:
	set(v):
		progress = clampf(v, 0.0, 1.0)
		queue_redraw()
## Share of the growth spent tracing the new outline.
var outline_share := 0.35
## The value the rim stands for at least, so a young personality does not fill it.
var min_extent := 0.5
## Draw the end names at the corners.
var show_labels := true
var font_size := 10


func _init() -> void:
	custom_minimum_size = Vector2(150, 118)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Shows `ends` with no growth.
func show_ends(ends: Array[float]) -> void:
	before = ends.duplicate()
	after = ends.duplicate()
	progress = 1.0


## The value the rim stands for: the largest end before or after, at least
## min_extent. Never shrinks during a growth, so the old shape never moves.
func extent() -> float:
	var m := min_extent
	for v in before + after:
		m = maxf(m, v)
	return m


## 0 to 1: how far the outline of the new shape is traced.
func outline_progress() -> float:
	if outline_share <= 0.0:
		return 1.0
	return clampf(progress / outline_share, 0.0, 1.0)


## 0 to 1: how far the fill has grown from the old shape to the new one.
func fill_progress() -> float:
	if outline_share >= 1.0:
		return 1.0 if progress >= 1.0 else 0.0
	return clampf((progress - outline_share) / (1.0 - outline_share), 0.0, 1.0)


## The values the fill shows now: before, growing toward after (eased).
func filled_values() -> Array[float]:
	var t := 1.0 - pow(1.0 - fill_progress(), 3.0)
	var out: Array[float] = []
	for i in Personality.ENDS.size():
		out.append(lerpf(_at(before, i), maxf(_at(before, i), _at(after, i)), t))
	return out


func _at(values: Array[float], i: int) -> float:
	return values[i] if i < values.size() else 0.0


func _radius() -> float:
	var label_room := (font_size * 1.6) if show_labels else 2.0
	return maxf(4.0, minf(size.x * 0.5 - label_room * 2.2, size.y * 0.5 - label_room))


func _centre() -> Vector2:
	return size * 0.5


## Corner `k` (0..5, clockwise from the top) at `fraction` of the rim.
func _corner(k: int, fraction: float) -> Vector2:
	var angle := -PI / 2.0 + k * TAU / 6.0
	return _centre() + Vector2(cos(angle), sin(angle)) * _radius() * fraction


func _shape(values: Array[float]) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var e := extent()
	for k in 6:
		pts.append(_corner(k, clampf(_at(values, CORNERS[k]) / e, 0.0, 1.0)))
	return pts


func _draw() -> void:
	for ring in [1.0 / 3.0, 2.0 / 3.0, 1.0]:
		var rim := PackedVector2Array()
		for k in 7:
			rim.append(_corner(k % 6, ring))
		draw_polyline(rim, GRID, 1.0)
	for k in 3:
		draw_line(_corner(k, 1.0), _corner(k + 3, 1.0), AXIS, 1.0)
	var old_shape := _shape(before)
	_fill(old_shape, OLD_FILL)
	var grew := not _same(before, after)
	if grew and fill_progress() > 0.0:
		_fill(_shape(filled_values()), NEW_FILL)
	var closed_old := old_shape.duplicate()
	closed_old.append(old_shape[0])
	draw_polyline(closed_old, OLD_LINE, 1.5)
	if grew and progress > 0.0:
		_trace(_shape(after), outline_progress())
	for k in 6:
		var p := _shape(filled_values() if grew else after)[k]
		draw_circle(p, 2.5, OUTLINE)
	if show_labels:
		_labels()


func _fill(shape: PackedVector2Array, color: Color) -> void:
	# A degenerate shape (several ends at 0) cannot be triangulated; draw it as
	# a fan of triangles from the centre instead, which always works.
	for k in 6:
		var a := shape[k]
		var b := shape[(k + 1) % 6]
		if (a - _centre()).cross(b - _centre()) != 0.0:
			draw_colored_polygon(PackedVector2Array([_centre(), a, b]), color)


## Draws the closed outline of `shape` up to `fraction` of its length.
func _trace(shape: PackedVector2Array, fraction: float) -> void:
	var lengths: Array[float] = []
	var total := 0.0
	for k in 6:
		var l := shape[k].distance_to(shape[(k + 1) % 6])
		lengths.append(l)
		total += l
	var left := total * fraction
	var pts := PackedVector2Array([shape[0]])
	for k in 6:
		if left <= 0.0:
			break
		var a := shape[k]
		var b := shape[(k + 1) % 6]
		if lengths[k] <= left:
			pts.append(b)
			left -= lengths[k]
		else:
			pts.append(a.lerp(b, left / maxf(lengths[k], 0.001)))
			left = 0.0
	if pts.size() >= 2:
		draw_polyline(pts, OUTLINE, 2.0)


func _labels() -> void:
	var font := get_theme_default_font()
	var fs := ScreenTheme.size(font_size) if is_inside_tree() else font_size
	for k in 6:
		var end := CORNERS[k]
		var text: String = Personality.ENDS[end].to_upper()
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var at := _corner(k, 1.0)
		var dir := (at - _centre()).normalized()
		var pos := at + dir * (fs * 0.6)
		if absf(dir.x) < 0.1:
			pos.x -= w * 0.5
		elif dir.x < 0.0:
			pos.x -= w
		pos.y += fs * 0.35 + (-fs * 0.3 if dir.y < -0.5 else (fs * 0.5 if dir.y > 0.5 else 0.0))
		var grew := _at(after, end) > _at(before, end) + 0.0001
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, LABEL_GREW if grew else LABEL)


static func _same(a: Array[float], b: Array[float]) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if not is_equal_approx(a[i], b[i]):
			return false
	return true
