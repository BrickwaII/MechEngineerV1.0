class_name MapRegion
extends RefCounted
## One territory on the overworld, as read from a region file. Plain data.

const MIN_DEFENSE := 0
const MAX_DEFENSE := 5
const MIN_PRESSURE_BASE := 1
const MAX_PRESSURE_BASE := 3
## Keys of `provides`.
const POWER := "power"
const ENERGY := "energy"
const MATERIAL := "material"
const RESOURCE_KEYS: Array[String] = [POWER, ENERGY, MATERIAL]

var id: String
var name: String
## A short label for crowded maps, such as "WA". The name when the file gives
## no "short_name".
var short_name: String
var kind: String
## Outline in map space: each coordinate 0 to 1 on a flat map, longitude and
## latitude in degrees on a globe. The region's main piece.
var polygon: PackedVector2Array
## Further pieces of the region (islands, a peninsula across a lake), from the
## file's optional "parts" list. Drawn and clicked like the polygon.
var parts: Array[PackedVector2Array] = []
## Where the node label sits, in map space. The polygon's centroid unless the
## file gives "label_at".
var label_at: Vector2
var adjacent: PackedStringArray
## Per-day amounts, keyed by POWER, ENERGY and MATERIAL.
var provides: Dictionary[String, int] = {}
var defense: int
var pressure_base: int
var starts_owned: bool


## Builds a region from one entry of a region file. Appends a message to
## `errors` for each problem found and returns null if there were any.
## `globe` reads points as longitude and latitude instead of 0 to 1.
static func from_dict(data: Variant, errors: Array[String], globe := false) -> MapRegion:
	if not data is Dictionary:
		errors.append("a region entry is not an object")
		return null
	var d: Dictionary = data
	var region := MapRegion.new()
	var before := errors.size()
	region.id = _string(d, "id", "?", errors)
	var where := "region '%s'" % region.id
	region.name = _string(d, "name", where, errors)
	region.short_name = _string(d, "short_name", where, errors) if d.has("short_name") else region.name
	region.kind = _string(d, "kind", where, errors)
	region.polygon = _points(d.get("polygon"), where + " polygon", errors, globe)
	if region.polygon.size() < 3:
		errors.append("%s polygon needs at least 3 points" % where)
	var parts: Variant = d.get("parts", [])
	if not parts is Array:
		errors.append("%s parts must be a list of polygons" % where)
	else:
		for part: Variant in parts:
			var points := _points(part, where + " part", errors, globe)
			if points.size() < 3:
				errors.append("%s part needs at least 3 points" % where)
			region.parts.append(points)
	if d.has("label_at"):
		var at := _points([d["label_at"]], where + " label_at", errors, globe)
		region.label_at = at[0] if at.size() == 1 else Vector2.ZERO
	else:
		region.label_at = _centroid(region.polygon)
	var adj: Variant = d.get("adjacent")
	if not adj is Array:
		errors.append("%s needs an 'adjacent' list" % where)
	else:
		for a: Variant in adj:
			if a is String:
				region.adjacent.append(a)
			else:
				errors.append("%s has a non-string adjacent id" % where)
	var provides: Variant = d.get("provides")
	if not provides is Dictionary:
		errors.append("%s needs a 'provides' object" % where)
	else:
		for key in RESOURCE_KEYS:
			region.provides[key] = _int((provides as Dictionary).get(key, 0), 0, 1000, "%s provides.%s" % [where, key], errors)
	region.defense = _int(d.get("defense"), MIN_DEFENSE, MAX_DEFENSE, where + " defense", errors)
	region.pressure_base = _int(d.get("pressure_base"), MIN_PRESSURE_BASE, MAX_PRESSURE_BASE, where + " pressure_base", errors)
	var owned: Variant = d.get("starts_owned", false)
	if not owned is bool:
		errors.append("%s starts_owned must be true or false" % where)
	region.starts_owned = owned == true
	return region if errors.size() == before else null


func is_adjacent_to(other_id: String) -> bool:
	return other_id in adjacent


## Every piece of the region's outline: the polygon, then the parts.
func shapes() -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = [polygon]
	out.append_array(parts)
	return out


## True when a map-space point lies inside the polygon or one of the parts.
func contains(point: Vector2) -> bool:
	for shape in shapes():
		if Geometry2D.is_point_in_polygon(point, shape):
			return true
	return false


static func _string(d: Dictionary, key: String, where: String, errors: Array[String]) -> String:
	var v: Variant = d.get(key)
	if not v is String or (v as String).is_empty():
		errors.append("%s needs a non-empty '%s'" % [where, key])
		return ""
	return v


static func _int(v: Variant, lo: int, hi: int, what: String, errors: Array[String]) -> int:
	# JSON numbers arrive as floats; accept only whole values.
	if not (v is float or v is int) or float(v) != floorf(float(v)):
		errors.append("%s must be a whole number" % what)
		return lo
	var i := int(v)
	if i < lo or i > hi:
		errors.append("%s must be %d to %d, got %d" % [what, lo, hi, i])
		return clampi(i, lo, hi)
	return i


## Reads [x, y] points. Flat maps keep each coordinate within 0 to 1; a globe
## (`globe` true) keeps longitude within -180 to 180 and latitude within -90
## to 90.
static func _points(v: Variant, what: String, errors: Array[String], globe := false) -> PackedVector2Array:
	var points := PackedVector2Array()
	if not v is Array:
		errors.append("%s must be a list of [x, y] points" % what)
		return points
	for p: Variant in v:
		if not p is Array or (p as Array).size() != 2 \
				or not (p[0] is float or p[0] is int) or not (p[1] is float or p[1] is int):
			errors.append("%s must be a list of [x, y] points" % what)
			return PackedVector2Array()
		var point := Vector2(float(p[0]), float(p[1]))
		if globe:
			if absf(point.x) > 180.0 or absf(point.y) > 90.0:
				errors.append("%s has a point outside longitude -180 to 180, latitude -90 to 90" % what)
		elif point.x < 0.0 or point.x > 1.0 or point.y < 0.0 or point.y > 1.0:
			errors.append("%s has a point outside 0 to 1" % what)
		points.append(point)
	return points


static func _centroid(points: PackedVector2Array) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for p in points:
		sum += p
	return sum / points.size()
