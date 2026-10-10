extends Control
## Draws each enemy's intent as an arrow from the enemy to its target, over
## the battlefield. The arrow's color and head say what it means (attack: red
## with a barbed head, heal: green with a round head, wait: blue and dashed),
## and a revised intent is drawn in the "changed" color. Arrows stay dim in the
## background; the one in focus (the next enemy to act, or the enemy under the
## pointer) is drawn bright, so only one leads the eye.

## Each arrow: {from: unit id, to: unit id, kind: "attack"|"heal"|"wait", changed: bool}.
var arrows: Array[Dictionary] = []
## The enemy whose arrow is in focus, or "".
var focus_id := ""
## Unit id -> its UnitView, to find where units stand.
var views: Dictionary = {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_arrows(p_arrows: Array[Dictionary], p_focus: String) -> void:
	arrows = p_arrows
	focus_id = p_focus
	queue_redraw()


func _process(_delta: float) -> void:
	# Cards can move as the layout settles; arrows follow.
	if not arrows.is_empty():
		queue_redraw()


func _draw() -> void:
	var dim := BattleArt.number("arrow_alpha_dim", 0.28)
	var bright := BattleArt.number("arrow_alpha_focus", 0.95)
	var width := BattleArt.number("arrow_width_px", 2.0)
	var to_local := get_global_transform().affine_inverse()
	for a in arrows:
		var from_view: Control = views.get(a.from)
		var to_view: Control = views.get(a.to)
		if from_view == null or to_view == null or not from_view.is_visible_in_tree() or not to_view.is_visible_in_tree():
			continue
		# From the enemy's front edge to the target's center.
		var from_rect := from_view.get_global_rect()
		var start: Vector2 = to_local * Vector2(from_rect.position.x + 8.0, from_rect.get_center().y)
		var end: Vector2 = to_local * to_view.center_global()
		var focused: bool = a.from == focus_id
		var color := kind_color(a.kind, a.changed)
		color.a = bright if focused else dim
		_draw_arrow(start, end, color, width + (1.0 if focused else 0.0), a.kind)


static func kind_color(kind: String, changed: bool) -> Color:
	if changed:
		return FeelData.color("changed")
	match kind:
		"heal":
			return FeelData.color("hp")
		"wait":
			return FeelData.color("energy")
	return FeelData.color("danger")


func _draw_arrow(start: Vector2, end: Vector2, color: Color, width: float, kind: String) -> void:
	# A shallow arc above the straight line; self-targets loop over the unit.
	var mid := (start + end) / 2.0
	var lift := clampf(start.distance_to(end) * 0.18, 24.0, 90.0)
	var control := mid + Vector2(0, -lift)
	if start.distance_to(end) < 4.0:
		control = start + Vector2(0, -70)
		end = start + Vector2(12, -8)
	var points := PackedVector2Array()
	var steps := 24
	# Start and stop short of the unit centers.
	for i in range(0, steps - 2):
		var t := float(i) / steps
		var p := start.lerp(control, t).lerp(control.lerp(end, t), t)
		points.append(p.round())
	if points.size() < 2:
		return
	if kind == "wait":
		for i in range(0, points.size() - 1, 2):
			draw_line(points[i], points[i + 1], color, width)
	else:
		draw_polyline(points, color, width)
	var tip := points[points.size() - 1]
	var dir := (tip - points[points.size() - 2]).normalized()
	var side := Vector2(-dir.y, dir.x)
	if kind == "heal":
		draw_circle(tip, width + 3.0, color)
	else:
		draw_colored_polygon(PackedVector2Array([
			tip + dir * 6.0, tip - dir * 6.0 + side * 6.0, tip - dir * 3.0, tip - dir * 6.0 - side * 6.0]), color)
