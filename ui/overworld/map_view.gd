extends Control
## Draws the regions of a Campaign's flat map, colored by standing, with a
## node on each: pressure ring and cause on held regions, defense pips on
## hostile ones (at the level they fight at, fortification in its own color,
## with a wall inside the border), the name, and what the region provides. Clicking a region
## selects it. Water crossings (bridges, ferries) are dashed lines.
##
## zoom and zoom_center move the camera over "zoom space": map space on a flat
## map. The act zoom animates them. While zoomed in, the inset draws the last
## act's map inside the rectangle it covers on this one.
##
## ui/overworld/globe_view.gd draws a globe instead by overriding the
## projection hooks: project_point(), project_shape(), view_to_map(),
## zoom_space_rect() and region_polygons().
##
## Lenses (ui/README.md rules 7 and 10): with `lens` set, each region shows
## only that lens as one small pin at its node, so the land stays clear:
##   defense    hostile regions' defense pips (fortified ones in their color)
##   pressure   held regions' pressure rings
##   resources  what each region gives, as icons and numbers
##   odds       your odds on regions in range ("62%"), from `odds_text`
## The selected region's pin also carries its name. "" keeps the full nodes.
##
## Feel (MapFx, data/feel/screens.json "map"): regions light up under the
## cursor, the selection outline pops, a capture sweeps the owned color out
## from the region's node with a ring and a flash, and pressure rings slide to
## new values and pulse once they reach the warning level.

const Palette := preload("res://ui/overworld/palette.gd")

signal region_selected(region_id: String)
## A right-click on a region: show everything about it (the DetailModal).
signal region_detail_requested(region_id: String)
## The pointer moved onto another region ("" for none).
signal region_hovered(region_id: String)

## Resource key -> its icon id in data/ui/icons.json (ui/README.md rule 1).
const CHIP_ICONS := {MapRegion.POWER: "grid_power", MapRegion.ENERGY: "map_energy", MapRegion.MATERIAL: "material"}
## Label icons are the 12 px art at 1x, to fit the 16 px label strips.
const LABEL_ICON := 12.0
const RING_RADIUS := 19.0
const RING_WIDTH := 6.0
const PIP := 7.0
const GAP := 4.0
const GRID_STEP := 40.0
## Compact nodes, for crowded maps.
const COMPACT_RING_RADIUS := 8.0
const COMPACT_RING_WIDTH := 3.5
const COMPACT_PIP := 4.0
const COMPACT_FONT := 10
## Node text sizes: the pixel font's 1x and 2x steps (data/feel/feel.json "theme").
const FONT_SMALL := 10
const FONT_NAME := 10
## Space kept clear around each node.
const NODE_MARGIN := 2.0
const CROSSING_DASH := 5.0
const CROSSING_WIDTH := 2.0
## Above this zoom the nodes are hidden; they would crowd the close-up.
const NODE_ZOOM_LIMIT := 1.15
## Fortification (R2-B escalation): the pips a region gained while left alone
## on alert, and the wall drawn inside its border.
const FORTIFY := Color("#ff7a59")
const FORTIFY_WALL_PX := 2.0

var campaign: Campaign:
	set(v):
		campaign = v
		_map_changed()
		queue_redraw()
var selected_id := "":
	set(v):
		selected_id = v
		queue_redraw()
## Camera scale, 1 for the whole map.
var zoom := 1.0:
	set(v):
		zoom = v
		queue_redraw()
## The zoom-space point at the middle of the view.
var zoom_center := Vector2(0.5, 0.5):
	set(v):
		zoom_center = v
		queue_redraw()
## The last act's map, drawn into inset_rect (zoom space) while inset_alpha > 0.
var inset_map: RegionMap
var inset_owned: PackedStringArray = []
var inset_rect := Rect2()
var inset_alpha := 0.0:
	set(v):
		inset_alpha = v
		queue_redraw()

## The moving parts: hover, selection pop, captures, ring fill and pulse.
var fx := MapFx.new()
## The lens the pins show: "defense", "pressure", "resources", "odds", or ""
## for the full nodes.
var lens := "":
	set(v):
		lens = v
		queue_redraw()
## region id -> [text, color] for the odds lens ("" text: no pin). Set by the
## overworld, which owns the estimates.
var odds_pin: Callable
## The pins drawn last frame: region id -> Rect2 in this control's coordinates.
var pin_rects := {}

const LENSES: Array[String] = ["defense", "pressure", "resources", "odds"]
## Pin text: the body size, so numbers on the map are as readable as anywhere.
const PIN_FONT := 20
const PIN_H := 24.0
const PIN_PAD := 4.0

## Map-space ends of each of the map's crossings, in its order.
var _crossing_ends: Array[PackedVector2Array] = []
## The map art's shape, from data (frame()).
static var _art := Vector2.ZERO
## True when the last draw had a pulsing ring, so the next frame redraws.
var _pulsing := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	resized.connect(queue_redraw)
	mouse_exited.connect(_hover_at.bind(null))


func _process(delta: float) -> void:
	var was_animating := fx.is_animating()
	fx.advance(delta)
	if was_animating or _pulsing or fx.is_animating():
		queue_redraw()


## Plays the takeover animation on a region that just became the player's.
func play_capture(region_id: String) -> void:
	fx.start_capture(region_id)
	queue_redraw()


## The region under a point in this control's coordinates, or "".
func region_at(point: Vector2) -> String:
	if campaign == null:
		return ""
	var at: Variant = view_to_map(point)
	return "" if at == null else campaign.map.region_at(at)


## Where a region's node sits, in this control's coordinates, or null when it
## is out of sight.
func label_position(region_id: String) -> Variant:
	return project_point(campaign.map.get_region(region_id).label_at)


func select(region_id: String) -> void:
	if region_id != selected_id:
		fx.selected()
		if not region_id.is_empty():
			SoundPlayer.fire(&"map_select")
	selected_id = region_id
	region_selected.emit(region_id)


# --- Projection hooks ------------------------------------------------------------

## A map-space point in this control's coordinates, or null when it is out of
## sight.
func project_point(p: Vector2) -> Variant:
	return _point(p)


## A map-space outline in this control's coordinates: the polygons it shows as,
## none when it is out of sight.
func project_shape(points: PackedVector2Array) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = [_to_view(points)]
	return out


## The map-space point under a point in this control's coordinates, or null
## when there is none.
func view_to_map(point: Vector2) -> Variant:
	var f := frame()
	return ((point - f.position) / f.size - Vector2(0.5, 0.5)) / zoom + zoom_center


## The zoom-space rectangle a map-space outline covers. The act zoom starts
## with it filling the view.
func zoom_space_rect(points: PackedVector2Array) -> Rect2:
	var rect := Rect2(points[0], Vector2.ZERO)
	for p in points:
		rect = rect.expand(p)
	return rect


## A region's outlines in this control's coordinates, as drawn.
func region_polygons(region: MapRegion) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for shape in region.shapes():
		out.append_array(project_shape(shape))
	return out


## Called when the campaign, and so maybe the map, changes.
func _map_changed() -> void:
	fx.reset()
	_crossing_ends.clear()
	if campaign == null:
		return
	for crossing in campaign.map.crossings:
		_crossing_ends.append(campaign.map.crossing_ends(crossing))


func _gui_input(event: InputEvent) -> void:
	if _right_click(event):
		return
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		select(region_at(click.position))
		accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		_hover_at(motion.position)


## A right-click on a region asks for its detail card. True when handled.
func _right_click(event: InputEvent) -> bool:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_RIGHT:
		return false
	var id := region_at(click.position)
	if not id.is_empty():
		region_detail_requested.emit(id)
	accept_event()
	return true


## Lights the region under `point` (null for none) and shows a hand over it.
func _hover_at(point: Variant) -> void:
	var id := "" if point == null else region_at(point)
	if id == fx.hovered_id:
		return
	fx.set_hovered(id)
	region_hovered.emit(id)
	# With a lens the overworld's hover card shows the region, Fortified flag
	# included; the full nodes keep their own fortify tooltip.
	if lens.is_empty():
		_tip_fortify(id)
	mouse_default_cursor_shape = Control.CURSOR_ARROW if id.is_empty() else Control.CURSOR_POINTING_HAND
	queue_redraw()


## Where zoom space's unit square sits in this control: the largest rect of
## the map art's shape ("map.frame" in data/ui/ui_kit.json), centered, so a
## bigger view shows a bigger map, never a stretched one. The backdrop fills
## the rest.
func frame() -> Rect2:
	if _art == Vector2.ZERO:
		_art = UiIcons.kit_vector("map.frame", Vector2(880, 580))
	var fitted := _art * minf(size.x / _art.x, size.y / _art.y)
	return Rect2(((size - fitted) / 2.0).round(), fitted)


## Zoom space to this control's coordinates.
func _point(p: Vector2) -> Vector2:
	var f := frame()
	return f.position + ((p - zoom_center) * zoom + Vector2(0.5, 0.5)) * f.size


func _to_view(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		out.append(_point(p))
	return out


# --- Drawing ---------------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.MAP_BACKGROUND)
	if campaign == null:
		return
	_draw_backdrop()
	for shape in campaign.map.land:
		for points in project_shape(shape):
			_fill(points, Palette.LAND)
	_draw_regions(4.0)
	for ends in _crossing_ends:
		_draw_crossing(ends)
	_draw_foreground()
	if inset_map != null and inset_alpha > 0.0:
		_draw_inset()
	_pulsing = false
	if zoom > NODE_ZOOM_LIMIT:
		return
	var entries := []
	for region in campaign.map.regions:
		var at: Variant = label_position(region.id)
		if at != null:
			entries.append([region, at, 0.0])
	_draw_nodes(entries)


## The region fills with their borders, hover light, captures in progress and
## the selection outline. `border` is the width of the gaps between regions.
func _draw_regions(border: float) -> void:
	var hover_lighten := ScreenFeel.number("map.hover_lighten")
	var polygons := {}
	for region in campaign.map.regions:
		polygons[region.id] = region_polygons(region)
		var fill := Palette.region_fill(campaign.standing(region.id), region.id == selected_id)
		var lit := fx.hover_amount(region.id)
		if lit > 0.0:
			fill = fill.lightened(hover_lighten * lit)
		var capturing := fx.is_capturing(region.id)
		var hostile := capturing or fx.is_held(region.id)
		for points: PackedVector2Array in polygons[region.id]:
			_fill(points, Palette.region_fill(Campaign.Standing.IN_RANGE, region.id == selected_id).lightened(hover_lighten * lit) if hostile else fill)
			if capturing:
				_draw_capture_fill(region, points, fill)
			_outline(points, Palette.MAP_BACKGROUND, border)
	for region in campaign.map.regions:
		var lit := fx.hover_amount(region.id)
		if lit > 0.0 and region.id != selected_id:
			for points: PackedVector2Array in polygons[region.id]:
				_outline(points, Color(Palette.TEXT_DIM, lit), ScreenFeel.number("map.hover_outline_px"))
	for region in campaign.map.regions:
		var levels := campaign.escalation.fortify_of(region.id)
		if levels > 0 and not campaign.is_owned(region.id):
			for points: PackedVector2Array in polygons[region.id]:
				_outline(points, Color(FORTIFY, 0.9), FORTIFY_WALL_PX * (levels + 1))
	for id: String in fx.capturing_ids():
		if polygons.has(id):
			_draw_capture_ring(campaign.map.get_region(id))
	if polygons.has(selected_id):
		var width := ScreenFeel.number("map.select_outline_px") + fx.select_pop_px()
		for points: PackedVector2Array in polygons[selected_id]:
			_outline(points, Palette.TEXT_BRIGHT, width)


## The owned color sweeping out from the region's node across `points`, and
## the flash as it starts.
func _draw_capture_fill(region: MapRegion, points: PackedVector2Array, fill: Color) -> void:
	var at: Variant = project_point(region.label_at)
	var progress := fx.capture_progress(region.id)
	var center: Vector2 = at if at != null else _middle(points)
	var reach := 0.0
	for p in points:
		reach = maxf(reach, p.distance_to(center))
	var eased := 1.0 - pow(1.0 - progress, 3.0)
	var circle := _circle(center, maxf(reach * eased, 1.0))
	for piece in Geometry2D.intersect_polygons(points, circle):
		_fill(piece, fill)
	var flash := fx.capture_flash(region.id)
	if flash > 0.0:
		_fill(points, Color(Palette.TEXT_BRIGHT, 0.6 * flash))


## The expanding ring of a capture, fading as it grows.
func _draw_capture_ring(region: MapRegion) -> void:
	if GameSettings.shared().reduced_motion:
		return
	var at: Variant = project_point(region.label_at)
	if at == null:
		return
	var progress := fx.capture_progress(region.id)
	var radius := ScreenFeel.number("map.capture_ring_px") * (0.4 + progress)
	draw_arc(at, radius, 0.0, TAU, 40, Color(Palette.ACCENT, 1.0 - progress), 3.0, true)


static func _circle(center: Vector2, radius: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 32:
		out.append(center + Vector2.from_angle(TAU * i / 32.0) * radius)
	return out


static func _middle(points: PackedVector2Array) -> Vector2:
	var sum := Vector2.ZERO
	for p in points:
		sum += p
	return sum / maxf(points.size(), 1)


## Draws nodes without overlaps. `entries` is [[region, view position, depth]];
## a bigger depth (nearer the viewer) wins a tie. The selected region comes
## first, then held regions, then those in range, then the rest. Each gets a
## full node (on a compact map only the selected one does) if it fits, a
## compact node if that fits, and nothing otherwise; held regions always show
## at least their compact ring.
func _draw_nodes(entries: Array) -> void:
	if lens in LENSES:
		_draw_lens_pins(entries)
		return
	var order := campaign.map.ids()
	entries.sort_custom(func(a: Array, b: Array) -> bool:
		var ra := _node_rank(a[0])
		var rb := _node_rank(b[0])
		if ra != rb:
			return ra < rb
		if a[2] != b[2]:
			return a[2] > b[2]
		return order.find(a[0].id) < order.find(b[0].id))
	var compact_map := campaign.tuning.node_style == MapTuning.NODE_COMPACT
	var placed: Array[Rect2] = []
	var plan := []
	for entry: Array in entries:
		var region: MapRegion = entry[0]
		var at: Vector2 = entry[1]
		if not compact_map or region.id == selected_id:
			var full := _node_rect(region, at, false)
			if region.id == selected_id or _fits(full, placed):
				placed.append(full)
				plan.append([region, at, false])
				continue
		var small := _node_rect(region, at, true)
		if _fits(small, placed) or campaign.is_owned(region.id):
			placed.append(small)
			plan.append([region, at, true])
	# Lowest rank first, so the selected node ends up on top.
	for i in range(plan.size() - 1, -1, -1):
		if plan[i][2]:
			_draw_compact_node(plan[i][0], plan[i][1])
		else:
			_draw_node(plan[i][0], plan[i][1])


## One small pin per region for the chosen lens; a pin that would cover
## another is left out (the selected region's always shows, with its name).
func _draw_lens_pins(entries: Array) -> void:
	var order := campaign.map.ids()
	entries.sort_custom(func(a: Array, b: Array) -> bool:
		var ra := _node_rank(a[0])
		var rb := _node_rank(b[0])
		if ra != rb:
			return ra < rb
		return order.find(a[0].id) < order.find(b[0].id))
	pin_rects.clear()
	var font := get_theme_default_font()
	var placed: Array[Rect2] = []
	var plan := []
	for entry: Array in entries:
		var region: MapRegion = entry[0]
		var parts := _pin_parts(region)
		var selected := region.id == selected_id
		if parts.is_empty() and not selected:
			continue
		var w := _pin_width(font, parts)
		var with_name := selected
		if with_name:
			w = maxf(w, font.get_string_size(region.name, HORIZONTAL_ALIGNMENT_LEFT, -1, PIN_FONT).x + PIN_PAD * 2.0)
		var h := PIN_H * (2.0 if with_name and not parts.is_empty() else 1.0)
		var at: Vector2 = entry[1]
		var rect := Rect2((at - Vector2(w, h) / 2.0).round(), Vector2(w, h).round())
		if not selected and not _fits(rect.grow(NODE_MARGIN), placed):
			continue
		placed.append(rect.grow(NODE_MARGIN))
		plan.append([region, rect, parts, with_name])
	for i in range(plan.size() - 1, -1, -1):
		var p: Array = plan[i]
		_draw_pin(font, p[0], p[1], p[2], p[3])
		pin_rects[(p[0] as MapRegion).id] = p[1]


## What a region's pin shows for the lens: [kind, value, color] parts, where
## kind is "pips", "ring", "icon" (an icon id) or "text".
func _pin_parts(region: MapRegion) -> Array:
	var owned := campaign.is_owned(region.id)
	match lens:
		"defense":
			if owned:
				return []
			return [["pips", campaign.defense_of(region.id), campaign.escalation.fortify_of(region.id)]]
		"pressure":
			if not owned:
				return []
			return [["ring", region.id, null]]
		"resources":
			var out := []
			for key in MapRegion.RESOURCE_KEYS:
				if region.provides[key] > 0:
					out.append(["icon", CHIP_ICONS[key], str(region.provides[key])])
			return out
		"odds":
			if owned or not odds_pin.is_valid():
				return []
			var o: Array = odds_pin.call(region.id)
			if o.is_empty() or str(o[0]).is_empty():
				return []
			return [["text", str(o[0]), o[1]]]
	return []


func _pin_width(font: Font, parts: Array) -> float:
	var w := PIN_PAD
	for part: Array in parts:
		match part[0]:
			"pips":
				w += MapRegion.MAX_DEFENSE * (PIP + 2.0) - 2.0 + PIN_PAD
			"ring":
				w += 18.0 + PIN_PAD
			"icon":
				w += LABEL_ICON + 2.0 + font.get_string_size(part[2], HORIZONTAL_ALIGNMENT_LEFT, -1, PIN_FONT).x + PIN_PAD
			"text":
				w += font.get_string_size(part[1], HORIZONTAL_ALIGNMENT_LEFT, -1, PIN_FONT).x + PIN_PAD
	return maxf(w, PIN_H)


func _draw_pin(font: Font, region: MapRegion, rect: Rect2, parts: Array, with_name: bool) -> void:
	draw_rect(rect, Palette.LABEL_BACK)
	if region.id == selected_id:
		draw_rect(rect, Palette.TEXT_BRIGHT, false, 1.0)
	var top := rect.position.y
	if with_name:
		var baseline := top + PIN_H / 2.0 + font.get_ascent(PIN_FONT) / 2.0 - 1.0
		draw_string(font, Vector2(rect.position.x + PIN_PAD, baseline), region.name, HORIZONTAL_ALIGNMENT_LEFT, -1, PIN_FONT, Palette.TEXT_BRIGHT)
		if parts.is_empty():
			return
		top += PIN_H
	var x := rect.position.x + (rect.size.x - _pin_width(font, parts)) / 2.0 + PIN_PAD
	var mid := top + PIN_H / 2.0
	for part: Array in parts:
		match part[0]:
			"pips":
				var level: int = part[1]
				var fortified: int = part[2]
				for i in MapRegion.MAX_DEFENSE:
					var pip := Rect2(x + i * (PIP + 2.0), mid - PIP / 2.0, PIP, PIP)
					if i < level:
						draw_rect(pip, FORTIFY if i >= level - fortified else Palette.DEFENSE)
					else:
						draw_rect(pip, Palette.DEFENSE, false, 1.0)
				x += MapRegion.MAX_DEFENSE * (PIP + 2.0) - 2.0 + PIN_PAD
			"ring":
				_draw_ring(Vector2(x + 9.0, mid), part[1], COMPACT_RING_RADIUS, COMPACT_RING_WIDTH, false)
				x += 18.0 + PIN_PAD
			"icon":
				draw_texture_rect(UiIcons.texture(part[1]), Rect2(x, mid - LABEL_ICON / 2.0, LABEL_ICON, LABEL_ICON), false)
				x += LABEL_ICON + 2.0
				draw_string(font, Vector2(x, mid + font.get_ascent(PIN_FONT) / 2.0 - 1.0), part[2], HORIZONTAL_ALIGNMENT_LEFT, -1, PIN_FONT, Palette.TEXT)
				x += font.get_string_size(part[2], HORIZONTAL_ALIGNMENT_LEFT, -1, PIN_FONT).x + PIN_PAD
			"text":
				draw_string(font, Vector2(x, mid + font.get_ascent(PIN_FONT) / 2.0 - 1.0), part[1], HORIZONTAL_ALIGNMENT_LEFT, -1, PIN_FONT, part[2])
				x += font.get_string_size(part[1], HORIZONTAL_ALIGNMENT_LEFT, -1, PIN_FONT).x + PIN_PAD


func _node_rank(region: MapRegion) -> int:
	if region.id == selected_id:
		return 0
	match campaign.standing(region.id):
		Campaign.Standing.OWNED:
			return 1
		Campaign.Standing.IN_RANGE:
			return 2
	return 3


static func _fits(rect: Rect2, placed: Array[Rect2]) -> bool:
	for other in placed:
		if rect.intersects(other):
			return false
	return true


## The rectangle a node covers, centered on `center`.
func _node_rect(region: MapRegion, center: Vector2, compact: bool) -> Rect2:
	var font := get_theme_default_font()
	var owned := campaign.is_owned(region.id)
	var w: float
	var h: float
	if compact:
		var top_h := COMPACT_RING_RADIUS * 2.0 + COMPACT_RING_WIDTH if owned else COMPACT_PIP + 4.0
		h = top_h + 2.0 + 14.0
		w = maxf(font.get_string_size(region.short_name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, COMPACT_FONT).x + 14.0,
			MapRegion.MAX_DEFENSE * (COMPACT_PIP + 1.0) + 3.0)
	else:
		var tag := _cause_tag(region.id) if owned else ""
		var top_h := RING_RADIUS * 2.0 + RING_WIDTH if owned else 16.0
		h = top_h + GAP + 18.0 + GAP + 16.0 + (GAP + 16.0 if not tag.is_empty() else 0.0)
		w = font.get_string_size(region.name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_NAME).x + 14.0
		w = maxf(w, _chips_width(font, _chips(region)))
		w = maxf(w, font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SMALL).x + 14.0)
		if not owned:
			w = maxf(w, LABEL_ICON + MapRegion.MAX_DEFENSE * (PIP + 2.0) + 15.0)
	return Rect2(center - Vector2(w, h) / 2.0, Vector2(w, h)).grow(NODE_MARGIN)


## What lies under the land and regions: water and the grid on a flat map.
func _draw_backdrop() -> void:
	for shape in campaign.map.water:
		for points in project_shape(shape):
			_fill(points, Palette.WATER)
	var x := GRID_STEP
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), Palette.MAP_GRID_LINE, 1.0)
		x += GRID_STEP
	var y := GRID_STEP
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), Palette.MAP_GRID_LINE, 1.0)
		y += GRID_STEP


## What lies over the regions but under the nodes. Nothing on a flat map.
func _draw_foreground() -> void:
	pass


func _draw_crossing(ends: PackedVector2Array) -> void:
	var a: Variant = project_point(ends[0])
	var b: Variant = project_point(ends[1])
	if a == null or b == null:
		return
	_dashed(a, b)


func _dashed(a: Vector2, b: Vector2) -> void:
	draw_dashed_line(a, b, Palette.CROSSING, CROSSING_WIDTH, CROSSING_DASH)
	draw_circle(a, CROSSING_WIDTH * 1.5, Palette.CROSSING)
	draw_circle(b, CROSSING_WIDTH * 1.5, Palette.CROSSING)


## Fills a polygon. One that does not triangulate (a self-touching outline)
## is skipped rather than drawn wrong.
func _fill(points: PackedVector2Array, color: Color) -> void:
	if points.size() < 3:
		return
	var indices := Geometry2D.triangulate_polygon(points)
	if indices.is_empty():
		return
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), indices, points, PackedColorArray([color]))


func _outline(points: PackedVector2Array, color: Color, width: float) -> void:
	if points.size() < 2:
		return
	var closed := points.duplicate()
	closed.append(points[0])
	draw_polyline(closed, color, width)


func _draw_inset() -> void:
	var back := Palette.MAP_BACKGROUND
	back.a = inset_alpha
	draw_rect(Rect2(_point(inset_rect.position), inset_rect.size * zoom * frame().size), back)
	var water := Palette.WATER
	water.a = inset_alpha
	for shape in inset_map.water:
		_fill(_inset_points(shape), water)
	var land := Palette.LAND
	land.a = inset_alpha
	for shape in inset_map.land:
		_fill(_inset_points(shape), land)
	for region in inset_map.regions:
		var fill := Palette.INSET_OWNED if region.id in inset_owned else Palette.INSET_HOSTILE
		fill.a = inset_alpha
		for shape in region.shapes():
			var points := _inset_points(shape)
			_fill(points, fill)
			_outline(points, back, 2.0)


func _inset_points(shape: PackedVector2Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for p in shape:
		points.append(_point(inset_rect.position + p * inset_rect.size))
	return points


func _draw_node(region: MapRegion, center: Vector2) -> void:
	var font := get_theme_default_font()
	var owned := campaign.is_owned(region.id)
	var tag := _cause_tag(region.id) if owned else ""
	var chips := _chips(region)
	var top_h := RING_RADIUS * 2.0 + RING_WIDTH if owned else 16.0
	var height := top_h + GAP + 18.0 + GAP + 16.0 + (GAP + 16.0 if not tag.is_empty() else 0.0)
	var top := center.y - height / 2.0

	if owned:
		_draw_ring(Vector2(center.x, top + top_h / 2.0), region.id, RING_RADIUS, RING_WIDTH, true)
	else:
		_draw_pips(font, Vector2(center.x, top), campaign.defense_of(region.id), campaign.escalation.fortify_of(region.id))
		_draw_fortify_mark(font, region.id, Vector2(center.x, top))
	top += top_h + GAP
	_label(font, region.name.to_upper(), center.x, top, FONT_NAME, Palette.TEXT_BRIGHT, 18.0)
	top += 18.0 + GAP
	_draw_chips(font, chips, center.x, top)
	top += 16.0 + GAP
	if not tag.is_empty():
		_label(font, tag, center.x, top, FONT_SMALL, _tag_color(region.id), 16.0)


## A small ring or pips over the short name.
func _draw_compact_node(region: MapRegion, center: Vector2) -> void:
	var font := get_theme_default_font()
	var top_h := COMPACT_RING_RADIUS * 2.0 + COMPACT_RING_WIDTH if campaign.is_owned(region.id) else COMPACT_PIP + 4.0
	var height := top_h + 2.0 + 14.0
	var top := center.y - height / 2.0
	if campaign.is_owned(region.id):
		_draw_ring(Vector2(center.x, top + top_h / 2.0), region.id, COMPACT_RING_RADIUS, COMPACT_RING_WIDTH, false)
	else:
		var w := MapRegion.MAX_DEFENSE * (COMPACT_PIP + 1.0) + 3.0
		var x := center.x - w / 2.0
		draw_rect(Rect2(x, top, w, top_h), Palette.LABEL_BACK)
		var level := campaign.defense_of(region.id)
		var fortified_from := level - campaign.escalation.fortify_of(region.id)
		for i in MapRegion.MAX_DEFENSE:
			var pip := Rect2(x + 2.0 + i * (COMPACT_PIP + 1.0), top + 2.0, COMPACT_PIP, COMPACT_PIP)
			if i < level:
				draw_rect(pip, FORTIFY if i >= fortified_from else Palette.DEFENSE)
			else:
				draw_rect(pip, Palette.DEFENSE, false, 1.0)
	_label(font, region.short_name.to_upper(), center.x, top + top_h + 2.0, COMPACT_FONT, Palette.TEXT_BRIGHT, 14.0)


## A held region's pressure ring. It slides to a new value rather than
## jumping, and from the warning level on a halo swells and fades in time:
## slowly, then fast once an attack is imminent. The halo and the color change
## together, so the warning reads without color.
func _draw_ring(at: Vector2, region_id: String, radius: float, width: float, with_text: bool) -> void:
	var t := campaign.tuning
	var real := campaign.pressure_of(region_id)
	var pressure := fx.ring_pressure(region_id, real)
	var ratio := clampf(pressure / t.forces_defense_at, 0.0, 1.0)
	var color := Palette.ACCENT
	if real >= t.imminent_at:
		color = Palette.DANGER
	elif real >= t.ring_warning_at:
		color = Palette.WARNING
	if real >= t.ring_warning_at:
		var swell := fx.ring_pulse_px(real, t)
		_pulsing = _pulsing or not GameSettings.shared().reduced_motion
		var max_swell := ScreenFeel.number("map.ring_pulse_px")
		var alpha := 0.55 * (1.0 - swell / maxf(max_swell, 0.001)) + 0.15
		draw_arc(at, radius + width / 2.0 + 1.0 + swell, 0.0, TAU, 48, Color(color, alpha), 2.0, true)
	draw_circle(at, radius + width / 2.0, Palette.BACKGROUND)
	draw_arc(at, radius, 0.0, TAU, 48, Color(1, 1, 1, 0.2), width, true)
	if ratio > 0.0:
		draw_arc(at, radius, -PI / 2.0, -PI / 2.0 + TAU * ratio, 48, color, width, true)
	if with_text:
		var font := get_theme_default_font()
		var text := "%d%%" % roundi(pressure)
		var font_size := FONT_SMALL
		draw_string(font, Vector2(at.x - 20.0, at.y + font.get_ascent(font_size) / 2.0), text, HORIZONTAL_ALIGNMENT_CENTER, 40.0, font_size, Palette.TEXT_BRIGHT)


## Defense pips; the last `fortified` of them, gained by fortifying, in the
## fortify color.
func _draw_pips(font: Font, top_center: Vector2, defense: int, fortified := 0) -> void:
	var label_w := LABEL_ICON
	var pips_w := MapRegion.MAX_DEFENSE * (PIP + 2.0) - 2.0
	var w := label_w + 5.0 + pips_w + 12.0
	var x := top_center.x - w / 2.0
	draw_rect(Rect2(x, top_center.y, w, 16.0), Palette.LABEL_BACK)
	draw_texture_rect(UiIcons.texture("defense_level"), Rect2(x + 6.0, top_center.y + 2.0, LABEL_ICON, LABEL_ICON), false)
	var px := x + 6.0 + label_w + 5.0
	for i in MapRegion.MAX_DEFENSE:
		var pip := Rect2(px + i * (PIP + 2.0), top_center.y + 4.5, PIP, PIP)
		if i < defense:
			draw_rect(pip, FORTIFY if i >= defense - fortified else Palette.DEFENSE)
		else:
			draw_rect(pip, Palette.DEFENSE, false, 1.0)


## The fortify icon and its levels to the right of the pips, on a fortified
## hostile region.
func _draw_fortify_mark(font: Font, region_id: String, top_center: Vector2) -> void:
	var levels := campaign.escalation.fortify_of(region_id)
	if levels <= 0:
		return
	var label_w := LABEL_ICON
	var x := top_center.x + (label_w + 5.0 + MapRegion.MAX_DEFENSE * (PIP + 2.0) - 2.0 + 12.0) / 2.0 + 2.0
	var text := "+%d" % levels
	var w := 16.0 + font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SMALL).x + 6.0
	draw_rect(Rect2(x, top_center.y, w, 16.0), Palette.LABEL_BACK)
	draw_texture_rect(UiIcons.texture("fortify"), Rect2(x + 2.0, top_center.y + 2.0, 12.0, 12.0), false)
	draw_string(font, Vector2(x + 16.0, top_center.y + 12.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SMALL, FORTIFY)


## The hover tooltip over a fortified hostile region; none elsewhere.
func _tip_fortify(region_id: String) -> void:
	if region_id.is_empty() or campaign == null or campaign.is_owned(region_id) \
			or campaign.escalation.fortify_of(region_id) <= 0:
		if has_meta(UiTooltip.META):
			remove_meta(UiTooltip.META)
			UiTooltip.hide_tooltip()
		return
	var levels := campaign.escalation.fortify_of(region_id)
	UiTooltip.attach(self, "Fortified", "%s dug in while left alone on Alert. Attack it to stop the digging." %
		campaign.map.get_region(region_id).name,
		"Defense +%d of %d, now %d" % [levels, campaign.escalation.max_fortify(), campaign.defense_of(region_id)], "fortify")
	UiTooltip.show_at(self, get_global_mouse_position() + Vector2(16, 16))


func _chips(region: MapRegion) -> Array:
	var chips := []
	for key in MapRegion.RESOURCE_KEYS:
		if region.provides[key] > 0:
			chips.append([key, str(region.provides[key])])
	return chips


func _chips_width(font: Font, chips: Array) -> float:
	if chips.is_empty():
		return 0.0
	var total := 6.0
	for chip: Array in chips:
		total += LABEL_ICON + 2.0 + font.get_string_size(chip[1], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SMALL).x + 6.0
	return total


func _draw_chips(font: Font, chips: Array, center_x: float, top: float) -> void:
	if chips.is_empty():
		return
	var widths := []
	for chip: Array in chips:
		widths.append(LABEL_ICON + 2.0 + font.get_string_size(chip[1], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SMALL).x)
	var total := _chips_width(font, chips)
	var x := center_x - total / 2.0
	draw_rect(Rect2(x, top, total, 16.0), Palette.LABEL_BACK)
	x += 6.0
	for i in chips.size():
		draw_texture_rect(UiIcons.texture(CHIP_ICONS[chips[i][0]]), Rect2(x, top + 2.0, LABEL_ICON, LABEL_ICON), false)
		draw_string(font, Vector2(x + LABEL_ICON + 2.0, top + 12.0), chips[i][1], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SMALL, Palette.TEXT)
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
