class_name RegionMap
extends RefCounted
## A set of regions loaded from one file in data/regions/. Swapping the file
## swaps the map; no code names a particular region.

## How the map is laid out: FLAT points run 0 to 1 across the view; GLOBE
## points are longitude and latitude, shown on a globe.
const FLAT := "flat"
const GLOBE := "globe"

var id: String
var name: String
## FLAT or GLOBE, from the file's optional "projection".
var projection := FLAT
## Where the outlines came from, from the file's optional "source". Credit only.
var source: String
## Regions in file order.
var regions: Array[MapRegion] = []
## Starting locations from the file's optional "starts" list, in file order.
var starts: Array[StartOption] = []
## Water drawn under the regions, from the file's optional "water" list of
## polygons in map space. Scenery only; it changes no rule.
var water: Array[PackedVector2Array] = []
## Neutral land no region holds, drawn over the water, from the file's
## optional "land" list. Scenery only.
var land: Array[PackedVector2Array] = []
## Water crossings (bridges, ferries, straits), from the file's optional
## "crossings" list: [{between: PackedStringArray of two region ids, name}].
## The two regions must list each other as adjacent; a crossing is how a map
## shows why regions across water are neighbors.
var crossings: Array[Dictionary] = []
## Where the previous act's map sits on this one, in map space, from the
## file's optional "zoom_inset". Empty when the file gives none.
var zoom_inset := PackedVector2Array()
## Problems found while loading. Empty when the map is usable.
var errors: Array[String] = []

var _by_id: Dictionary[String, MapRegion] = {}


## Reads a region file. Check `errors` on the result before using it.
static func load_file(path: String) -> RegionMap:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		var map := RegionMap.new()
		map.errors.append("cannot read %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return map
	return from_json(text)


static func from_json(text: String) -> RegionMap:
	var json := JSON.new()
	if json.parse(text) != OK:
		var map := RegionMap.new()
		map.errors.append("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
		return map
	return from_dict(json.data)


static func from_dict(data: Variant) -> RegionMap:
	var map := RegionMap.new()
	if not data is Dictionary:
		map.errors.append("a region file must hold an object")
		return map
	var d: Dictionary = data
	map.id = str(d.get("id", ""))
	map.name = str(d.get("name", ""))
	map.source = str(d.get("source", ""))
	map.projection = str(d.get("projection", FLAT))
	if map.id.is_empty():
		map.errors.append("the region file needs an 'id'")
	if map.projection != FLAT and map.projection != GLOBE:
		map.errors.append("'projection' must be '%s' or '%s'" % [FLAT, GLOBE])
	var globe := map.is_globe()
	var list: Variant = d.get("regions")
	if not list is Array or (list as Array).is_empty():
		map.errors.append("the region file needs a non-empty 'regions' list")
		return map
	for entry: Variant in list:
		var region := MapRegion.from_dict(entry, map.errors, globe)
		if region == null:
			continue
		if map._by_id.has(region.id):
			map.errors.append("region id '%s' is used twice" % region.id)
			continue
		map.regions.append(region)
		map._by_id[region.id] = region
	map._read_starts(d.get("starts", []))
	map.water = map._read_shapes(d.get("water", []), "water", globe)
	map.land = map._read_shapes(d.get("land", []), "land", globe)
	map._read_crossings(d.get("crossings", []))
	if d.has("zoom_inset"):
		map.zoom_inset = MapRegion._points(d["zoom_inset"], "zoom_inset", map.errors, globe)
		if map.zoom_inset.size() < 2:
			map.errors.append("zoom_inset needs at least 2 points")
	map._check_links()
	return map


func is_valid() -> bool:
	return errors.is_empty()


func is_globe() -> bool:
	return projection == GLOBE


## The region under a map-space point (longitude and latitude on a globe), or
## "". Later regions win where outlines overlap, as they are drawn on top.
func region_at(point: Vector2) -> String:
	for i in range(regions.size() - 1, -1, -1):
		if regions[i].contains(point):
			return regions[i].id
	return ""


## The crossing between two regions, in either order, or an empty dictionary.
func crossing_between(a: String, b: String) -> Dictionary:
	for crossing in crossings:
		var between: PackedStringArray = crossing["between"]
		if (between[0] == a and between[1] == b) or (between[0] == b and between[1] == a):
			return crossing
	return {}


## Where a crossing is drawn: the closest pair of outline points of its two
## regions, in map space. [from, to].
func crossing_ends(crossing: Dictionary) -> PackedVector2Array:
	var between: PackedStringArray = crossing["between"]
	var a := get_region(between[0])
	var b := get_region(between[1])
	var best := PackedVector2Array([a.label_at, b.label_at])
	var best_d := INF
	for shape_a in a.shapes():
		for p in shape_a:
			for shape_b in b.shapes():
				for q in shape_b:
					var d := p.distance_squared_to(q)
					if d < best_d:
						best_d = d
						best = PackedVector2Array([p, q])
	return best


func has_region(region_id: String) -> bool:
	return _by_id.has(region_id)


## The region with this id, or null.
func get_region(region_id: String) -> MapRegion:
	return _by_id.get(region_id)


func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for region in regions:
		out.append(region.id)
	return out


func starting_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for region in regions:
		if region.starts_owned:
			out.append(region.id)
	return out


## The starts a player chooses from: the file's "starts", or one start made
## from the starts_owned regions when the file lists none.
func start_options() -> Array[StartOption]:
	if not starts.is_empty():
		return starts
	var only: Array[StartOption] = [StartOption.default_for(self)]
	return only


## The start with this id, or null. "" names the first start option.
func get_start(start_id: String) -> StartOption:
	var options := start_options()
	if start_id.is_empty():
		return options[0]
	for start in options:
		if start.id == start_id:
			return start
	return null


func _read_starts(list: Variant) -> void:
	if not list is Array:
		errors.append("'starts' must be a list")
		return
	var seen := {}
	for entry: Variant in list:
		var start := StartOption.from_dict(entry, errors)
		if start == null:
			continue
		if seen.has(start.id):
			errors.append("start id '%s' is used twice" % start.id)
			continue
		seen[start.id] = true
		starts.append(start)


func _read_shapes(list: Variant, what: String, globe: bool) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	if not list is Array:
		errors.append("'%s' must be a list of polygons" % what)
		return out
	for shape: Variant in list:
		var points := MapRegion._points(shape, "a %s polygon" % what, errors, globe)
		if points.size() >= 3:
			out.append(points)
		else:
			errors.append("a %s polygon needs at least 3 points" % what)
	return out


func _read_crossings(list: Variant) -> void:
	if not list is Array:
		errors.append("'crossings' must be a list")
		return
	for entry: Variant in list:
		var between: Variant = entry.get("between") if entry is Dictionary else null
		var crossing_name: Variant = entry.get("name") if entry is Dictionary else null
		if not between is Array or (between as Array).size() != 2 or not between[0] is String \
				or not between[1] is String or not crossing_name is String or (crossing_name as String).is_empty():
			errors.append("a crossing needs 'between' (two region ids) and a 'name'")
			continue
		crossings.append({"between": PackedStringArray(between), "name": crossing_name})


func _check_links() -> void:
	for region in regions:
		for other_id in region.adjacent:
			if other_id == region.id:
				errors.append("region '%s' lists itself as adjacent" % region.id)
			elif not _by_id.has(other_id):
				errors.append("region '%s' lists unknown neighbor '%s'" % [region.id, other_id])
			elif not _by_id[other_id].is_adjacent_to(region.id):
				errors.append("region '%s' lists '%s' as adjacent but not the other way round" % [region.id, other_id])
	for crossing in crossings:
		var between: PackedStringArray = crossing["between"]
		if not _by_id.has(between[0]) or not _by_id.has(between[1]):
			errors.append("crossing '%s' names an unknown region" % crossing["name"])
		elif not _by_id[between[0]].is_adjacent_to(between[1]):
			errors.append("crossing '%s' joins regions that are not adjacent" % crossing["name"])
	if not regions.is_empty() and starting_ids().is_empty():
		errors.append("no region has starts_owned set")
	for start in starts:
		var listed := {}
		for region_id in start.regions:
			if not _by_id.has(region_id):
				errors.append("start '%s' lists unknown region '%s'" % [start.id, region_id])
			elif listed.has(region_id):
				errors.append("start '%s' lists '%s' twice" % [start.id, region_id])
			listed[region_id] = true
