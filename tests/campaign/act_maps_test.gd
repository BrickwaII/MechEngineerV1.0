extends GdUnitTestSuite
## The three shipped act maps, headless: greater Seattle, North America and
## the world. They load, their adjacency is sound, water crossings are there,
## and they follow real geography.

const ACTS := "res://data/tuning/acts.json"
const SEATTLE := "res://data/regions/greater_seattle.json"
const NORTH_AMERICA := "res://data/regions/north_america.json"
const WORLD := "res://data/regions/world.json"


func _load(path: String) -> RegionMap:
	var map := RegionMap.load_file(path)
	assert_array(map.errors).override_failure_message("%s: %s" % [path, map.errors]).is_empty()
	return map


func _maps() -> Array[RegionMap]:
	var plan := ActPlan.load_file(ACTS)
	var maps: Array[RegionMap] = []
	for act in plan.act_count():
		maps.append(plan.load_map(act))
	return maps


func test_all_three_acts_load() -> void:
	var plan := ActPlan.load_file(ACTS)
	assert_array(plan.errors).is_empty()
	assert_int(plan.act_count()).is_equal(3)
	var ids := []
	for act in plan.act_count():
		var map := plan.load_map(act)
		assert_array(map.errors).override_failure_message("act %d: %s" % [act + 1, map.errors]).is_empty()
		assert_array(plan.load_tuning(act).errors).is_empty()
		ids.append(map.id)
	assert_array(ids).is_equal(["greater_seattle", "north_america", "world"])
	assert_bool(plan.load_map(0).is_globe()).is_false()
	assert_bool(plan.load_map(1).is_globe()).is_false()
	assert_bool(plan.load_map(2).is_globe()).is_true()


func test_adjacency_is_symmetric_with_no_orphans_and_one_network() -> void:
	for map in _maps():
		for region in map.regions:
			assert_int(region.adjacent.size()).override_failure_message("%s: %s has no neighbor" % [map.id, region.id]).is_greater(0)
			for other_id in region.adjacent:
				assert_bool(map.get_region(other_id).is_adjacent_to(region.id)) \
					.override_failure_message("%s: %s -> %s is one way" % [map.id, region.id, other_id]).is_true()
		# Every region can be reached from every other.
		var reached := {map.regions[0].id: true}
		var queue := [map.regions[0].id]
		while not queue.is_empty():
			for other_id in map.get_region(queue.pop_front()).adjacent:
				if not reached.has(other_id):
					reached[other_id] = true
					queue.append(other_id)
		assert_int(reached.size()).override_failure_message("%s is split into islands" % map.id).is_equal(map.regions.size())


func test_every_act_has_water_crossings_between_neighbors() -> void:
	for map in _maps():
		assert_int(map.crossings.size()).override_failure_message("%s has no crossings" % map.id).is_greater(0)
		for crossing in map.crossings:
			var between: PackedStringArray = crossing["between"]
			assert_bool(map.get_region(between[0]).is_adjacent_to(between[1])).is_true()


func test_every_outline_triangulates() -> void:
	for map in _maps():
		var shapes: Array[PackedVector2Array] = map.land.duplicate()
		for region in map.regions:
			shapes.append_array(region.shapes())
		for shape in shapes:
			assert_bool(Geometry2D.triangulate_polygon(shape).is_empty()) \
				.override_failure_message("%s: an outline does not triangulate" % map.id).is_false()


func test_every_label_sits_on_its_region_or_close_by() -> void:
	# Labels are placed deep inside the main outline; a few are nudged by hand.
	for map in _maps():
		for region in map.regions:
			if not region.contains(region.label_at):
				var nearest := INF
				for p in region.polygon:
					nearest = minf(nearest, p.distance_to(region.label_at))
				var limit := 3.0 if map.is_globe() else 0.05
				assert_float(nearest).override_failure_message("%s: %s label is far from it" % [map.id, region.id]).is_less(limit)


func test_greater_seattle_is_cities_with_water_between() -> void:
	var map := _load(SEATTLE)
	assert_int(map.regions.size()).is_between(16, 22)
	for city in ["seattle", "shoreline", "bothell", "kirkland", "redmond", "bellevue", "mercer_island",
			"sammamish", "issaquah", "renton", "tukwila", "burien", "bainbridge_island", "bremerton",
			"port_orchard", "poulsbo", "vashon"]:
		assert_bool(map.has_region(city)).override_failure_message("no %s" % city).is_true()
	# Puget Sound and Lake Washington are water: the islands and the far shore
	# are reached by bridges and ferries only.
	var seattle := map.get_region("seattle")
	assert_bool(map.crossing_between("seattle", "bellevue").is_empty()).is_false()
	assert_bool(map.crossing_between("seattle", "mercer_island").is_empty()).is_false()
	assert_bool(map.crossing_between("seattle", "bainbridge_island").is_empty()).is_false()
	assert_bool(map.crossing_between("seattle", "bremerton").is_empty()).is_false()
	for island in ["mercer_island", "vashon"]:
		for other_id in map.get_region(island).adjacent:
			assert_bool(map.crossing_between(island, other_id).is_empty()) \
				.override_failure_message("%s touches %s by land" % [island, other_id]).is_false()
	assert_bool(seattle.is_adjacent_to("kirkland")).is_false()
	assert_bool(seattle.is_adjacent_to("redmond")).is_false()
	# North is up and west is left: Seattle lies west of Bellevue, Shoreline
	# north of Seattle, Bremerton across the Sound to the west.
	assert_float(seattle.label_at.x).is_less(map.get_region("bellevue").label_at.x)
	assert_float(map.get_region("shoreline").label_at.y).is_less(seattle.label_at.y)
	assert_float(map.get_region("bremerton").label_at.x).is_less(map.get_region("bainbridge_island").label_at.x)
	assert_float(map.get_region("kent").label_at.y).is_greater(map.get_region("renton").label_at.y)
	# One water sheet under everything, land on top.
	assert_int(map.water.size()).is_equal(1)
	assert_str(map.source).contains("Natural Earth")


func test_greater_seattle_starts_keep_their_trait_kinds() -> void:
	var map := _load(SEATTLE)
	assert_int(map.starts.size()).is_equal(3)
	var two := map.get_start("north_end")
	assert_int(two.regions.size()).is_equal(2)
	var yard := map.get_start("bremerton_yard")
	assert_array(Array(yard.regions)).contains_exactly(["bremerton"])
	assert_int(yard.income_bonus[MapRegion.POWER]).is_equal(3)
	assert_float(yard.material).is_equal(10.0)
	var substation := map.get_start("issaquah_substation")
	assert_float(substation.pressure_rate_factor).is_equal(0.5)
	for start in map.starts:
		for region_id in start.regions:
			assert_bool(region_id == "seattle").override_failure_message("a start holds the city").is_false()


func test_north_america_is_the_lower_48_with_neighbors() -> void:
	var map := _load(NORTH_AMERICA)
	for id in ["washington", "california", "texas", "florida", "maine", "michigan", "new_york"]:
		assert_bool(map.has_region(id)).is_true()
	for id in ["baja_california", "sonora", "chihuahua", "coahuila", "nuevo_leon", "tamaulipas",
			"british_columbia", "alberta", "saskatchewan", "manitoba", "ontario", "quebec"]:
		assert_bool(map.has_region(id)).override_failure_message("no %s" % id).is_true()
	# Tiny states are grouped: 48 states make 44 regions.
	for group in ["chesapeake", "southern_new_england", "northern_new_england"]:
		assert_bool(map.has_region(group)).is_true()
	for small in ["rhode_island", "delaware", "connecticut", "vermont"]:
		assert_bool(map.has_region(small)).is_false()
	# Real borders.
	assert_bool(map.get_region("washington").is_adjacent_to("oregon")).is_true()
	assert_bool(map.get_region("washington").is_adjacent_to("british_columbia")).is_true()
	assert_bool(map.get_region("texas").is_adjacent_to("coahuila")).is_true()
	assert_bool(map.get_region("washington").is_adjacent_to("california")).is_false()
	assert_bool(map.get_region("michigan").is_adjacent_to("ontario")).is_true()
	assert_bool(map.get_region("michigan").parts.size()).is_greater(0)
	# The act 1 metro sits in western Washington.
	assert_int(map.zoom_inset.size()).is_greater(2)
	var middle := Vector2.ZERO
	for p in map.zoom_inset:
		middle += p
	assert_str(map.region_at(middle / map.zoom_inset.size())).is_equal("washington")
	assert_bool(map.get_region("washington").starts_owned).is_true()


func test_the_world_finds_the_right_region_by_longitude_and_latitude() -> void:
	var map := _load(WORLD)
	var places := {
		Vector2(-122.3, 47.6): "united_states",  # Seattle
		Vector2(-74.0, 40.7): "united_states",  # New York
		Vector2(-150.0, 61.2): "united_states",  # Anchorage
		Vector2(-79.4, 43.7): "canada",  # Toronto
		Vector2(-99.1, 19.4): "mexico_central",  # Mexico City
		Vector2(-47.9, -15.8): "brazil",  # Brasilia
		Vector2(-0.1, 51.5): "british_isles",  # London
		Vector2(2.35, 48.85): "western_europe",  # Paris
		Vector2(-52.3, 4.9): "north_andes",  # Cayenne, French Guiana
		Vector2(13.4, 52.5): "central_europe",  # Berlin
		Vector2(37.6, 55.75): "russia_west",  # Moscow
		Vector2(82.9, 55.0): "siberia",  # Novosibirsk
		Vector2(31.2, 30.0): "north_africa",  # Cairo
		Vector2(77.2, 28.6): "south_asia",  # Delhi
		Vector2(116.4, 39.9): "china",  # Beijing
		Vector2(139.7, 35.7): "east_asia",  # Tokyo
		Vector2(151.2, -33.9): "australia",  # Sydney
		Vector2(174.8, -41.3): "oceania",  # Wellington
		Vector2(18.4, -33.9): "southern_africa",  # Cape Town
	}
	for at: Vector2 in places:
		assert_str(map.region_at(at)).override_failure_message("%s should be %s" % [at, places[at]]).is_equal(places[at])
	assert_str(map.region_at(Vector2(-30.0, 30.0))).is_empty()  # Mid-Atlantic
	assert_bool(map.get_region("united_states").is_adjacent_to("siberia")).is_true()
	assert_bool(map.crossing_between("united_states", "siberia").is_empty()).is_false()
	# North America sits in the United States.
	assert_int(map.zoom_inset.size()).is_greater(2)
	assert_bool(map.get_region("united_states").starts_owned).is_true()
