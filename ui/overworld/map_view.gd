extends Control
## Draws the regions of a Campaign's map, colored by standing, with a node on
## each: pressure ring and cause on held regions, defense pips on hostile ones,
## the name, and what the region provides. Clicking a region selects it.

const Palette := preload("res://ui/overworld/palette.gd")

signal region_selected(region_id: String)

const SHORT_NAMES := {MapRegion.POWER: "PWR", MapRegion.ENERGY: "ENG", MapRegion.MATERIAL: "MAT"}
const RING_RADIUS := 19.0
const RING_WIDTH := 6.0
const PIP := 7.0
const GAP := 4.0
const GRID_STEP := 40.0

var campaign: Campaign:
	set(v):
		campaign = v
		queue_redraw()
var selected_id := "":
	set(v):
		selected_id = v
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	resized.connect(queue_redraw)


## The region under a point in this control's coordinates, or "".
func region_at(point: Vector2) -> String:
	if campaign == null:
		return ""
	for i in range(campaign.map.regions.size() - 1, -1, -1):
		var region := campaign.map.regions[i]
		if Geometry2D.is_point_in_polygon(point, _to_view(region.polygon)):
			return region.id
	return ""


## Where a region's node sits, in this control's coordinates.
func label_position(region_id: String) -> Vector2:
	return campaign.map.get_region(region_id).label_at * size


func select(region_id: String) -> void:
	selected_id = region_id
	region_selected.emit(region_id)


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		select(region_at(click.position))
		accept_event()


func _to_view(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		out.append(p * size)
	return out


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.MAP_BACKGROUND)
	var x := GRID_STEP
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), Palette.MAP_GRID_LINE, 1.0)
		x += GRID_STEP
	var y := GRID_STEP
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), Palette.MAP_GRID_LINE, 1.0)
		y += GRID_STEP
	if campaign == null:
		return
	for region in campaign.map.regions:
		var points := _to_view(region.polygon)
		draw_colored_polygon(points, Palette.region_fill(campaign.standing(region.id), region.id == selected_id))
		var outline := points.duplicate()
		outline.append(points[0])
		draw_polyline(outline, Palette.MAP_BACKGROUND, 4.0)
	if not selected_id.is_empty() and campaign.map.has_region(selected_id):
		var points := _to_view(campaign.map.get_region(selected_id).polygon)
		points.append(points[0])
		draw_polyline(points, Palette.TEXT_BRIGHT, 2.0)
	for region in campaign.map.regions:
		_draw_node(region)


func _draw_node(region: MapRegion) -> void:
	var font := get_theme_default_font()
	var owned := campaign.is_owned(region.id)
	var tag := _cause_tag(region.id) if owned else ""
	var chips := _chips(region)
	var top_h := RING_RADIUS * 2.0 + RING_WIDTH if owned else 16.0
	var height := top_h + GAP + 18.0 + GAP + 16.0 + (GAP + 16.0 if not tag.is_empty() else 0.0)
	var center := label_position(region.id)
	var top := center.y - height / 2.0

	if owned:
		_draw_ring(Vector2(center.x, top + top_h / 2.0), campaign.pressure_of(region.id))
	else:
		_draw_pips(font, Vector2(center.x, top), region.defense)
	top += top_h + GAP
	_label(font, region.name.to_upper(), center.x, top, 13, Palette.TEXT_BRIGHT, 18.0)
	top += 18.0 + GAP
	_draw_chips(font, chips, center.x, top)
	top += 16.0 + GAP
	if not tag.is_empty():
		_label(font, tag, center.x, top, 10, _tag_color(region.id), 16.0)


func _draw_ring(at: Vector2, pressure: float) -> void:
	var t := campaign.tuning
	var ratio := clampf(pressure / t.forces_defense_at, 0.0, 1.0)
	var color := Palette.ACCENT
	if pressure >= t.imminent_at:
		color = Palette.DANGER
	elif pressure >= t.ring_warning_at:
		color = Palette.WARNING
	draw_circle(at, RING_RADIUS + RING_WIDTH / 2.0, Palette.BACKGROUND)
	draw_arc(at, RING_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.2), RING_WIDTH, true)
	if ratio > 0.0:
		draw_arc(at, RING_RADIUS, -PI / 2.0, -PI / 2.0 + TAU * ratio, 48, color, RING_WIDTH, true)
	var font := get_theme_default_font()
	var text := "%d%%" % roundi(pressure)
	draw_string(font, Vector2(at.x - 20.0, at.y + 4.0), text, HORIZONTAL_ALIGNMENT_CENTER, 40.0, 11, Palette.TEXT_BRIGHT)


func _draw_pips(font: Font, top_center: Vector2, defense: int) -> void:
	var label_w := font.get_string_size("DEF", HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	var pips_w := MapRegion.MAX_DEFENSE * (PIP + 2.0) - 2.0
	var w := label_w + 5.0 + pips_w + 12.0
	var x := top_center.x - w / 2.0
	draw_rect(Rect2(x, top_center.y, w, 16.0), Palette.LABEL_BACK)
	draw_string(font, Vector2(x + 6.0, top_center.y + 12.0), "DEF", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Palette.DEFENSE_TEXT)
	var px := x + 6.0 + label_w + 5.0
	for i in MapRegion.MAX_DEFENSE:
		var pip := Rect2(px + i * (PIP + 2.0), top_center.y + 4.5, PIP, PIP)
		if i < defense:
			draw_rect(pip, Palette.DEFENSE)
		else:
			draw_rect(pip, Palette.DEFENSE, false, 1.0)


func _chips(region: MapRegion) -> Array:
	var chips := []
	for key in MapRegion.RESOURCE_KEYS:
		if region.provides[key] > 0:
			chips.append([key, "%s %d" % [SHORT_NAMES[key], region.provides[key]]])
	return chips


func _draw_chips(font: Font, chips: Array, center_x: float, top: float) -> void:
	if chips.is_empty():
		return
	var widths := []
	var total := 6.0
	for chip: Array in chips:
		var w := 8.0 + 3.0 + font.get_string_size(chip[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		widths.append(w)
		total += w + 6.0
	var x := center_x - total / 2.0
	draw_rect(Rect2(x, top, total, 16.0), Palette.LABEL_BACK)
	x += 6.0
	for i in chips.size():
		draw_rect(Rect2(x, top + 4.0, 8.0, 8.0), Palette.resource_color(chips[i][0]))
		draw_string(font, Vector2(x + 11.0, top + 12.0), chips[i][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Palette.TEXT)
		x += widths[i] + 6.0


func _label(font: Font, text: String, center_x: float, top: float, font_size: int, color: Color, h: float) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 14.0
	draw_rect(Rect2(center_x - w / 2.0, top, w, h), Palette.LABEL_BACK)
	var baseline := top + h / 2.0 + font.get_ascent(font_size) / 2.0 - 1.0
	draw_string(font, Vector2(center_x - w / 2.0 + 7.0, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## The cause line under a held node: who is pressing on it.
func _cause_tag(region_id: String) -> String:
	var attacker := campaign.attacker_of(region_id)
	if attacker == null:
		return "UPRISING"
	return "ATTACK FROM %s" % attacker.name.to_upper()


func _tag_color(region_id: String) -> Color:
	var pressure := campaign.pressure_of(region_id)
	if pressure >= campaign.tuning.imminent_at:
		return Palette.TAG_DANGER
	if pressure >= campaign.tuning.cause_warning_at:
		return Palette.TAG_WARNING
	return Palette.TEXT_DIM
