extends "res://ui/overworld/map_view.gd"
## The map of a globe-projection region file (act 3), drawn as an orthographic
## globe the player drags to turn. Regions, nodes, crossings, colors and the
## territory panel work as on the flat map; only the projection differs.
##
## How it draws: every outline (longitude and latitude) is split into short
## edges once, turned into points on a unit sphere, and kept. Each redraw turns
## those points into the view's frame (east, north, toward the viewer), clips
## each outline to the near half of the sphere, follows the rim between where
## an outline leaves and re-enters it, and drops the depth: that is the
## orthographic projection. Clicks run it backwards: the point on the disk
## gives a point on the sphere, then a longitude and latitude, and
## RegionMap.region_at() finds the region there, so hit-testing matches what
## is drawn at any rotation.
##
## Zoom space (what zoom and zoom_center move over) is the unzoomed view, 0 to
## 1 on each axis, so the act zoom works as on the flat map.

## Degrees between graticule lines, and between the points that draw them.
const GRATICULE_STEP := 30.0
const GRATICULE_POINT_STEP := 5.0
## Degrees between the points of a rim arc.
const RIM_STEP := 4.0
const CROSSING_POINTS := 24

## The longitude and latitude at the middle of the globe.
var center_lon := 0.0:
	set(v):
		center_lon = wrapf(v, -180.0, 180.0)
		queue_redraw()
var center_lat := 0.0:
	set(v):
		center_lat = clampf(v, -_max_tilt(), _max_tilt())
		queue_redraw()

## Per region id, its shapes as unit-sphere points.
var _region_spheres: Dictionary[String, Array] = {}
var _land_spheres: Array[PackedVector3Array] = []
var _graticule: Array[PackedVector3Array] = []
var _crossing_arcs: Array[PackedVector3Array] = []

## Where the left button went down, while it is down; null otherwise.
var _press_at: Variant = null
var _dragging := false


## Turns the globe so this longitude and latitude faces the viewer.
func look_at_lonlat(lonlat: Vector2) -> void:
	center_lon = lonlat.x
	center_lat = lonlat.y


## Turns the globe as dragging the mouse by `relative` pixels does: the
## surface follows the mouse.
func drag_by(relative: Vector2) -> void:
	var per_pixel := campaign.tuning.globe_degrees_per_pixel / zoom
	center_lon -= relative.x * per_pixel
	center_lat += relative.y * per_pixel


## The globe's radius in pixels at zoom 1.
func radius() -> float:
	var fraction := campaign.tuning.globe_size if campaign != null else 1.0
	return minf(size.x, size.y) * fraction / 2.0


## Where a longitude and latitude sits on the unit disk (x east, y north) and
## how squarely it faces the viewer (z, 1 at the middle, below 0 behind).
func to_view_frame(lonlat: Vector2) -> Vector3:
	return _turn(_sphere(lonlat))


# --- Projection hooks ------------------------------------------------------------

func project_point(p: Vector2) -> Variant:
	var v := to_view_frame(p)
	return _disk_to_view(Vector2(v.x, v.y)) if v.z >= 0.0 else null


func project_shape(points: PackedVector2Array) -> Array[PackedVector2Array]:
	return _project_sphere_shape(_to_sphere(points))


func view_to_map(point: Vector2) -> Variant:
	var q := (point / size - Vector2(0.5, 0.5)) / zoom + zoom_center
	var r := radius()
	var disk := Vector2((q.x - 0.5) * size.x / r, -(q.y - 0.5) * size.y / r)
	if disk.length_squared() > 1.0:
		return null
	var z := sqrt(1.0 - disk.length_squared())
	var basis := _basis()
	var v: Vector3 = basis[0] * disk.x + basis[1] * disk.y + basis[2] * z
	return Vector2(rad_to_deg(atan2(v.y, v.x)), rad_to_deg(asin(clampf(v.z, -1.0, 1.0))))


## The zoom-space rectangle of an outline's points that face the viewer.
func zoom_space_rect(points: PackedVector2Array) -> Rect2:
	var rect := Rect2()
	var first := true
	for p in points:
		var v := to_view_frame(p)
		if v.z < 0.0:
			continue
		var at := _disk_to_zoom_space(Vector2(v.x, v.y))
		rect = Rect2(at, Vector2.ZERO) if first else rect.expand(at)
		first = false
	return rect


func label_position(region_id: String) -> Variant:
	var v := to_view_frame(campaign.map.get_region(region_id).label_at)
	if v.z < campaign.tuning.globe_node_min_facing:
		return null
	return _disk_to_view(Vector2(v.x, v.y))


func _map_changed() -> void:
	super._map_changed()
	_region_spheres.clear()
	_land_spheres.clear()
	_crossing_arcs.clear()
	_graticule.clear()
	if campaign == null:
		return
	for region in campaign.map.regions:
		var shapes: Array[PackedVector3Array] = []
		for shape in region.shapes():
			shapes.append(_to_sphere(shape))
		_region_spheres[region.id] = shapes
	for shape in campaign.map.land:
		_land_spheres.append(_to_sphere(shape))
	for ends in _crossing_ends:
		var a := _sphere(ends[0])
		var b := _sphere(ends[1])
		var arc := PackedVector3Array()
		for i in CROSSING_POINTS + 1:
			arc.append(a.slerp(b, float(i) / CROSSING_POINTS))
		_crossing_arcs.append(arc)
	_build_graticule()
	# Face the network.
	if not campaign.state.owned.is_empty():
		look_at_lonlat(campaign.map.get_region(campaign.state.owned[0]).label_at)


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			_press_at = button.position
			_dragging = false
		else:
			if _press_at != null and not _dragging:
				select(region_at(button.position))
			_press_at = null
			_dragging = false
		accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _press_at != null:
		if not _dragging and motion.position.distance_to(_press_at) > campaign.tuning.globe_drag_threshold:
			_dragging = true
		if _dragging:
			drag_by(motion.relative)
		accept_event()
	if motion != null:
		_hover_at(null if _dragging else motion.position)


func region_polygons(region: MapRegion) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for shape: PackedVector3Array in _region_spheres.get(region.id, []):
		out.append_array(_project_sphere_shape(shape))
	return out


# --- Drawing ---------------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.MAP_BACKGROUND)
	if campaign == null:
		return
	_draw_backdrop()
	for shape in _land_spheres:
		for points in _project_sphere_shape(shape):
			_fill(points, Palette.LAND)
	_draw_regions(3.0)
	for arc in _crossing_arcs:
		_draw_arc_on_globe(arc)
	_draw_foreground()
	if inset_map != null and inset_alpha > 0.0:
		_draw_inset()
	_pulsing = false
	if zoom > NODE_ZOOM_LIMIT:
		return
	# Nodes facing the viewer most squarely win where nodes would overlap.
	var entries := []
	for region in campaign.map.regions:
		var at: Variant = label_position(region.id)
		if at != null:
			entries.append([region, at, to_view_frame(region.label_at).z])
	_draw_nodes(entries)


## The ocean and the lines of latitude and longitude.
func _draw_backdrop() -> void:
	var center := _disk_to_view(Vector2.ZERO)
	draw_circle(center, radius() * zoom, Palette.WATER)
	for line in _graticule:
		var view := _turn_all(line)
		for i in view.size() - 1:
			if view[i].z >= 0.0 and view[i + 1].z >= 0.0:
				draw_line(_disk_to_view(Vector2(view[i].x, view[i].y)),
					_disk_to_view(Vector2(view[i + 1].x, view[i + 1].y)), Palette.GRATICULE, 1.0)


func _draw_foreground() -> void:
	draw_arc(_disk_to_view(Vector2.ZERO), radius() * zoom, 0.0, TAU, 96, Palette.GLOBE_RIM, 2.0, true)


## A crossing as a dashed great-circle arc, the part that faces the viewer.
func _draw_arc_on_globe(arc: PackedVector3Array) -> void:
	var view := _turn_all(arc)
	for i in view.size() - 1:
		if view[i].z >= 0.0 and view[i + 1].z >= 0.0 and i % 2 == 0:
			draw_line(_disk_to_view(Vector2(view[i].x, view[i].y)),
				_disk_to_view(Vector2(view[i + 1].x, view[i + 1].y)), Palette.CROSSING, CROSSING_WIDTH)
	for end in [view[0], view[view.size() - 1]]:
		if end.z >= 0.0:
			draw_circle(_disk_to_view(Vector2(end.x, end.y)), CROSSING_WIDTH * 1.5, Palette.CROSSING)


# --- Sphere math -------------------------------------------------------------------

static func _sphere(lonlat: Vector2) -> Vector3:
	var lon := deg_to_rad(lonlat.x)
	var lat := deg_to_rad(lonlat.y)
	return Vector3(cos(lat) * cos(lon), cos(lat) * sin(lon), sin(lat))


## An outline as sphere points, its edges split so none spans more than the
## tuning's edge_degrees; the split points follow the outline's longitude and
## latitude, so straight borders such as the 49th parallel curve correctly.
func _to_sphere(points: PackedVector2Array) -> PackedVector3Array:
	var step := campaign.tuning.globe_edge_degrees
	var out := PackedVector3Array()
	for i in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		var n := ceili(maxf(absf(b.x - a.x), absf(b.y - a.y)) / step)
		for k in maxi(1, n):
			out.append(_sphere(a.lerp(b, float(k) / maxi(1, n))))
	return out


## East, north and toward-the-viewer axes for the current rotation.
func _basis() -> Array[Vector3]:
	var lon := deg_to_rad(center_lon)
	var lat := deg_to_rad(center_lat)
	var toward := Vector3(cos(lat) * cos(lon), cos(lat) * sin(lon), sin(lat))
	var east := Vector3(-sin(lon), cos(lon), 0.0)
	var north := Vector3(-sin(lat) * cos(lon), -sin(lat) * sin(lon), cos(lat))
	return [east, north, toward]


func _turn(v: Vector3) -> Vector3:
	var basis := _basis()
	return Vector3(v.dot(basis[0]), v.dot(basis[1]), v.dot(basis[2]))


func _turn_all(points: PackedVector3Array) -> PackedVector3Array:
	var basis := _basis()
	var out := PackedVector3Array()
	out.resize(points.size())
	for i in points.size():
		var v := points[i]
		out[i] = Vector3(v.dot(basis[0]), v.dot(basis[1]), v.dot(basis[2]))
	return out


## A sphere outline clipped to the near half and projected: the points behind
## the rim are dropped, and where the outline leaves the near half and comes
## back, the rim between the two crossings closes it. Empty when none of it
## faces the viewer.
func _project_sphere_shape(shape: PackedVector3Array) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var view := _turn_all(shape)
	var n := view.size()
	var start := -1
	for i in n:
		if view[i].z >= 0.0:
			start = i
			break
	if start < 0:
		return out
	var disk := PackedVector2Array()
	var exit_at: Variant = null
	# Start on a near point, so every exit comes before its re-entry.
	for k in range(1, n + 1):
		var prev := view[(start + k - 1) % n]
		var cur := view[(start + k) % n]
		if cur.z >= 0.0:
			if prev.z < 0.0:
				var entry := _rim_point(prev, cur)
				if exit_at != null:
					_append_rim(disk, exit_at, entry)
				disk.append(entry)
				exit_at = null
			disk.append(Vector2(cur.x, cur.y))
		elif prev.z >= 0.0:
			exit_at = _rim_point(prev, cur)
			disk.append(exit_at)
	if disk.size() < 3:
		return out
	var points := PackedVector2Array()
	points.resize(disk.size())
	for i in disk.size():
		points[i] = _disk_to_view(disk[i])
	out.append(points)
	return out


## Where the edge from a near point to a far one crosses the rim, on the unit circle.
static func _rim_point(a: Vector3, b: Vector3) -> Vector2:
	var t := a.z / (a.z - b.z)
	var p := a.lerp(b, t)
	var flat := Vector2(p.x, p.y)
	return flat.normalized() if flat.length_squared() > 0.0 else Vector2.RIGHT


## Rim points from `from` to `to`, the short way round, ends left out.
static func _append_rim(disk: PackedVector2Array, from: Vector2, to: Vector2) -> void:
	var a0 := from.angle()
	var turn := wrapf(to.angle() - a0, -PI, PI)
	var steps := ceili(absf(rad_to_deg(turn)) / RIM_STEP)
	for i in range(1, steps):
		disk.append(Vector2.from_angle(a0 + turn * float(i) / steps))


func _disk_to_zoom_space(disk: Vector2) -> Vector2:
	var r := radius()
	return Vector2(0.5 + disk.x * r / size.x, 0.5 - disk.y * r / size.y)


func _disk_to_view(disk: Vector2) -> Vector2:
	return _point(_disk_to_zoom_space(disk))


func _max_tilt() -> float:
	return campaign.tuning.globe_max_tilt if campaign != null else 90.0


func _build_graticule() -> void:
	var lon := -180.0
	while lon < 180.0:
		var line := PackedVector3Array()
		var lat := -90.0
		while lat <= 90.0:
			line.append(_sphere(Vector2(lon, lat)))
			lat += GRATICULE_POINT_STEP
		_graticule.append(line)
		lon += GRATICULE_STEP
	var lat := -90.0 + GRATICULE_STEP
	while lat < 90.0:
		var line := PackedVector3Array()
		var lon2 := -180.0
		while lon2 <= 180.0:
			line.append(_sphere(Vector2(lon2, lat)))
			lon2 += GRATICULE_POINT_STEP
		_graticule.append(line)
		lat += GRATICULE_STEP
