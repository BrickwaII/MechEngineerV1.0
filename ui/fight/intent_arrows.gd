extends Control
## Draws each enemy's intent as an arrow from the enemy to its target, over
## the battlefield, with the number it carries on a badge along the arrow:
## the damage it would deal, the hp it would restore, or the guard it would
## give. A skull on the badge marks a hit that would down its target. The
## arrow's color and head say what it means (attack: red with a barbed head,
## heal: green with a round head, wait: blue and dashed, guard: blue), and a
## revised intent is drawn in the "changed" color. Arrows stay dim in the
## background; the one in focus (the next enemy to act, or the enemy under the
## pointer) is drawn bright, so only one leads the eye. Badges stay readable
## on every arrow.
##
## While a choice is previewed the screen also passes the player's own arrow
## (drawn in the preview color), the enemy arrows as they would stand after
## the choice (changed ones in the "changed" color with the old number struck
## out), and the arrows the choice would replace, as faint ghosts.
## Sizes and colors: data/feel/battle_readout.json.

const KO_ICON := preload("res://assets/fight/icons/ko_skull.png")

## Each arrow: {from: unit id, to: unit id, kind: "attack"|"heal"|"wait"|"guard",
## changed: bool, badge: ArrowBadge or null, player: bool, ghost: bool}.
var arrows: Array[Dictionary] = []
## The enemy whose arrow is in focus, or "".
var focus_id := ""
## Unit id -> its UnitView, to find where units stand.
var views: Dictionary = {}
## Explains a badge for its tooltip: badge -> {"title", "body", "math"}
## (math: BattleMath lines). Unset: badges have no tooltip.
var describe: Callable
## Each badge drawn last frame: {"badge": ArrowBadge, "rect": Rect2 (local)}.
var badge_rects: Array[Dictionary] = []

## Invisible controls over the badges that carry their tooltips.
var _hotspots: Array[Control] = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_arrows(p_arrows: Array[Dictionary], p_focus: String) -> void:
	arrows = p_arrows
	focus_id = p_focus
	queue_redraw()


## The badges drawn now, as text, ghosts left out: "rust_hound#1>stub_bolt 6 KO".
## For tests.
func badge_texts() -> Array[String]:
	var out: Array[String] = []
	for a in arrows:
		var badge: ArrowBadge = a.get("badge")
		if badge == null or a.get("ghost", false):
			continue
		var line := "%s>%s %s" % [a.from, a.to, badge.text()]
		if badge.knocks_out:
			line += " KO"
		if a.get("changed", false) and badge.old_amount != null:
			line += " was %s" % badge.old_amount.text()
		out.append(line)
	return out


func _process(_delta: float) -> void:
	# Cards can move as the layout settles; arrows follow.
	if not arrows.is_empty():
		queue_redraw()


func _draw() -> void:
	var dim := BattleArt.number("arrow_alpha_dim", 0.28)
	var bright := BattleArt.number("arrow_alpha_focus", 0.95)
	var width := BattleArt.number("arrow_width_px", 2.0)
	var ghost_alpha := ReadoutStyle.number("badge.ghost_alpha", 0.14)
	var to_local := get_global_transform().affine_inverse()
	var badges: Array = []
	badge_rects.clear()
	for a in arrows:
		var from_view: Control = views.get(a.from)
		var to_view: Control = views.get(a.to)
		if from_view == null or to_view == null or not from_view.is_visible_in_tree() or not to_view.is_visible_in_tree():
			continue
		var player: bool = a.get("player", false)
		var ghost: bool = a.get("ghost", false)
		# From the actor's front edge to the target's center.
		var from_rect := from_view.get_global_rect()
		var front_x := from_rect.end.x - 8.0 if player else from_rect.position.x + 8.0
		var start: Vector2 = to_local * Vector2(front_x, from_rect.get_center().y)
		var end: Vector2 = to_local * to_view.center_global()
		# The player's own arrow and every arrow its choice would change lead the eye.
		var focused: bool = player or a.from == focus_id or a.get("changed", false)
		var color := ReadoutStyle.color("player_arrow.color") if player else kind_color(a.kind, a.get("changed", false))
		color.a = ghost_alpha if ghost else (bright if focused else dim)
		var w := ReadoutStyle.number("player_arrow.width_px", 3.0) if player else width + (1.0 if focused else 0.0)
		var points := _arrow_points(start, end, player, a.from == a.to)
		_draw_arrow(points, color, w, a.kind)
		var badge: ArrowBadge = a.get("badge")
		if badge != null and not ghost and points.size() >= 2:
			var at := points[clampi(int(roundf((points.size() - 1) * ReadoutStyle.number("badge.at", 0.62))), 0, points.size() - 1)]
			badges.append([badge, at, focused, a.get("changed", false), player])
	# Badges on top of every arrow, the focused ones last.
	badges.sort_custom(func(x: Array, y: Array) -> bool: return not x[2] and y[2])
	for b: Array in badges:
		badge_rects.append({"badge": b[0], "rect": _draw_badge(b[0], b[1], b[2], b[3], b[4])})
	_sync_hotspots.call_deferred()


## One hotspot per badge, placed over it, with the badge's tooltip: what it
## is and how its number comes about (ui/README.md rule 15).
func _sync_hotspots() -> void:
	if not describe.is_valid():
		return
	while _hotspots.size() < badge_rects.size():
		var h := Control.new()
		h.name = "BadgeHotspot%d" % _hotspots.size()
		add_child(h)
		_hotspots.append(h)
	for i in _hotspots.size():
		var h := _hotspots[i]
		h.visible = i < badge_rects.size()
		if not h.visible:
			continue
		var r: Rect2 = badge_rects[i]["rect"]
		h.position = r.position
		h.size = r.size
		var badge: ArrowBadge = badge_rects[i]["badge"]
		if not h.has_meta(&"badge") or h.get_meta(&"badge") != badge:
			h.set_meta(&"badge", badge)
			var d: Dictionary = describe.call(badge)
			UiTooltip.attach(h, str(d.get("title", "")), str(d.get("body", "")), str(d.get("numbers", "")),
				str(d.get("icon", "")), d.get("math", []))


## The hotspot over the badge drawn for `from` -> `to`, or null. For tests.
func hotspot_for(from_id: String, to_id: String) -> Control:
	for i in mini(badge_rects.size(), _hotspots.size()):
		var b: ArrowBadge = badge_rects[i]["badge"]
		if b.from_id == from_id and b.to_id == to_id:
			return _hotspots[i]
	return null


static func kind_color(kind: String, changed: bool) -> Color:
	if changed:
		return FeelData.color("changed")
	match kind:
		"heal":
			return FeelData.color("hp")
		"wait":
			return FeelData.color("energy")
		"guard":
			return FeelData.color("selected")
	return FeelData.color("danger")


## The arrow as a polyline: a shallow arc above the straight line (below it
## for the player's own arrow, so the two never sit on each other);
## self-targets loop over the unit. Starts and stops short of the units.
func _arrow_points(start: Vector2, end: Vector2, below := false, self_target := false) -> PackedVector2Array:
	var mid := (start + end) / 2.0
	var lift := clampf(start.distance_to(end) * 0.18, 24.0, 90.0)
	var control := mid + Vector2(0, lift if below else -lift)
	if self_target or start.distance_to(end) < 4.0:
		start = end
		control = start + Vector2(0, -70)
		end = start + Vector2(12, -8)
	var points := PackedVector2Array()
	var steps := 24
	for i in range(0, steps - 2):
		var t := float(i) / steps
		var p := start.lerp(control, t).lerp(control.lerp(end, t), t)
		points.append(p.round())
	return points


func _draw_arrow(points: PackedVector2Array, color: Color, width: float, kind: String) -> void:
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


## A badge centered on `at`: the number, a skull before it for a KO, and the
## old number struck out before it when the choice changed it. Returns its rect.
func _draw_badge(badge: ArrowBadge, at: Vector2, focused: bool, changed: bool, player := false) -> Rect2:
	var font := PixelTheme.font()
	var font_size := int(ReadoutStyle.number("badge.font_size", 10))
	var pad := Vector2(ReadoutStyle.number("badge.pad_x", 4), ReadoutStyle.number("badge.pad_y", 3))
	var icon_px := ReadoutStyle.number("badge.ko_icon_px", 12) if badge.knocks_out else 0.0
	var label := badge.text()
	var old := badge.old_amount.text() if changed and badge.old_amount != null else ""
	var text_w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var old_w := font.get_string_size(old + " ", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x if not old.is_empty() else 0.0
	var gap := 2.0 if icon_px > 0.0 else 0.0
	var inner_h := maxf(icon_px, font.get_height(font_size))
	var size_px := Vector2(icon_px + gap + old_w + text_w, inner_h) + pad * 2.0
	var rect := Rect2((at - size_px / 2.0).round(), size_px.round())
	var alpha := 1.0 if focused else ReadoutStyle.number("badge.dim_alpha", 0.8)
	var border_color := ReadoutStyle.color("badge.changed") if changed else ReadoutStyle.color("badge." + badge.kind)
	if player:
		border_color = ReadoutStyle.color("player_arrow.badge_border")
	if badge.knocks_out:
		border_color = ReadoutStyle.color("badge.ko")
	var border := ReadoutStyle.number("badge.ko_border_px" if badge.knocks_out else "badge.border_px", 1)
	draw_rect(rect, Color(ReadoutStyle.color("badge.background"), alpha))
	draw_rect(rect, Color(border_color, alpha), false, border)
	var x := rect.position.x + pad.x
	if icon_px > 0.0:
		draw_texture_rect(KO_ICON, Rect2(Vector2(x, rect.position.y + (rect.size.y - icon_px) / 2.0).round(), Vector2(icon_px, icon_px)),
			false, Color(1, 1, 1, alpha))
		x += icon_px + gap
	var baseline := rect.position.y + floorf((rect.size.y + font.get_ascent(font_size)) / 2.0) - 1.0
	if not old.is_empty():
		var old_color := Color(ReadoutStyle.color("badge.old_text"), alpha)
		draw_string(font, Vector2(x, baseline), old, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, old_color)
		var strike_y := baseline - floorf(font.get_ascent(font_size) / 2.0)
		draw_line(Vector2(x - 1, strike_y), Vector2(x + old_w - 3, strike_y), old_color, 1.0)
		x += old_w
	var text_color := Color(ReadoutStyle.color("badge.text"), alpha)
	draw_string(font, Vector2(x + 1, baseline + 1), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, alpha))
	draw_string(font, Vector2(x, baseline), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
	return rect
