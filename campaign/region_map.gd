class_name RegionMap
extends RefCounted
## A set of regions loaded from one file in data/regions/. Swapping the file
## swaps the map; no code names a particular region.

var id: String
var name: String
## Regions in file order.
var regions: Array[MapRegion] = []
## Starting locations from the file's optional "starts" list, in file order.
var starts: Array[StartOption] = []
## Water drawn under the regions, from the file's optional "water" list of
## polygons in map space. Scenery only; it changes no rule.
var water: Array[PackedVector2Array] = []
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
	if map.id.is_empty():
		map.errors.append("the region file needs an 'id'")
	var list: Variant = d.get("regions")
	if not list is Array or (list as Array).is_empty():
		map.errors.append("the region file needs a non-empty 'regions' list")
		return map
	for entry: Variant in list:
		var region := MapRegion.from_dict(entry, map.errors)
		if region == null:
			continue
		if map._by_id.has(region.id):
			map.errors.append("region id '%s' is used twice" % region.id)
			continue
		map.regions.append(region)
		map._by_id[region.id] = region
	map._read_starts(d.get("starts", []))
	var water: Variant = d.get("water", [])
	if not water is Array:
		map.errors.append("'water' must be a list of polygons")
	else:
		for shape: Variant in water:
			var points := MapRegion._points(shape, "a water polygon", map.errors)
			if points.size() >= 3:
				map.water.append(points)
			else:
				map.errors.append("a water polygon needs at least 3 points")
	map._check_links()
	return map


func is_valid() -> bool:
	return errors.is_empty()


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


func _check_links() -> void:
	for region in regions:
		for other_id in region.adjacent:
			if other_id == region.id:
				errors.append("region '%s' lists itself as adjacent" % region.id)
			elif not _by_id.has(other_id):
				errors.append("region '%s' lists unknown neighbor '%s'" % [region.id, other_id])
			elif not _by_id[other_id].is_adjacent_to(region.id):
				errors.append("region '%s' lists '%s' as adjacent but not the other way round" % [region.id, other_id])
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
