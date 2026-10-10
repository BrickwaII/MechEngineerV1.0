extends GdUnitTestSuite
## Every shipped map variant of the three acts, headless: the cities around
## Lake Washington, North America and the world. They load, their adjacency is
## sound, water crossings are there, and they follow real geography.

const ACTS := "res://data/tuning/acts.json"


func _plan() -> ActPlan:
	var plan := ActPlan.load_file(ACTS)
	assert_array(plan.errors).is_empty()
	return plan


## Every variant's map, as [act, variant, map].
func _all() -> Array:
	var plan := _plan()
	var out := []
	for act in plan.act_count():
		for variant: Dictionary in plan.variants(act):
			out.append([act, variant, RegionMap.load_file(variant["region_file"])])
	return out


func _load(id: String) -> RegionMap:
	var map := RegionMap.load_file("res://data/regions/%s.json" % id)
	assert_array(map.errors).override_failure_message("%s: %s" % [id, map.errors]).is_empty()
	return map


func test_every_variant_loads_and_is_named_by_its_map() -> void:
	var counts := {}
	for entry: Array in _all():
		var act: int = entry[0]
		var variant: Dictionary = entry[1]
		var map: RegionMap = entry[2]
		assert_array(map.errors).override_failure_message("%s: %s" % [variant["id"], map.errors]).is_empty()
		assert_str(map.id).is_equal(variant["id"])
		assert_bool(map.is_globe()).is_equal(act == 2)
		if act > 0:
			assert_bool(map.has_region(variant["zoom_focus"])) \
				.override_failure_message("%s has no %s" % [map.id, variant["zoom_focus"]]).is_true()
			assert_int(map.zoom_inset.size()).is_greater(2)
		counts[map.id] = map.regions.size()
	assert_dict(counts).is_equal({
		"lake_washington_8": 8, "lake_washington_12": 12, "lake_washington_16": 16, "lake_washington_22": 22,
		"north_america_19": 19, "north_america_33": 33, "north_america_57": 57,
		"world_8": 8, "world_20": 20, "world_39": 39,
	})


func test_adjacency_is_symmetric_with_no_orphans_and_one_network() -> void:
	for entry: Array in _all():
		var map: RegionMap = entry[2]
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


func test_every_variant_has_water_crossings_between_neighbors() -> void:
	for entry: Array in _all():
		var map: RegionMap = entry[2]
		assert_int(map.crossings.size()).override_failure_message("%s has no crossings" % map.id).is_greater(0)
		for crossing in map.crossings:
			var between: PackedStringArray = crossing["between"]
			assert_bool(map.get_region(between[0]).is_adjacent_to(between[1])).is_true()


func test_every_outline_triangulates() -> void:
	for entry: Array in _all():
		var map: RegionMap = entry[2]
		var shapes: Array[PackedVector2Array] = map.land.duplicate()
		for region in map.regions:
			shapes.append_array(region.shapes())
		for shape in shapes:
			assert_bool(Geometry2D.triangulate_polygon(shape).is_empty()) \
				.override_failure_message("%s: an outline does not triangulate" % map.id).is_false()


func test_every_label_sits_on_its_region() -> void:
	for entry: Array in _all():
		var map: RegionMap = entry[2]
		for region in map.regions:
			assert_bool(region.contains(region.label_at)) \
				.override_failure_message("%s: %s label is off it" % [map.id, region.id]).is_true()


func test_act1_variants_ring_lake_washington() -> void:
	var plan := _plan()
	for variant: Dictionary in plan.variants(0):
		var map := _load(variant["id"])
		assert_bool(map.has_region("bellevue")).is_true()
		assert_bool(map.has_region("mercer_island")).is_true()
		# Seattle is one region or several districts.
		var seattle := []
		for region in map.regions:
			if region.id.contains("seattle") or region.id == "ballard":
				seattle.append(region)
		assert_int(seattle.size()).override_failure_message("%s has no Seattle" % map.id).is_greater(0)
		# The lake is water: Seattle reaches Bellevue and Mercer Island only
		# over the bridges, and Mercer Island touches nothing by land.
		for region: MapRegion in seattle:
			if region.is_adjacent_to("bellevue"):
				assert_bool(map.crossing_between(region.id, "bellevue").is_empty()).is_false()
			assert_bool(region.is_adjacent_to("kirkland")).is_false()
		for other_id in map.get_region("mercer_island").adjacent:
			assert_bool(map.crossing_between("mercer_island", other_id).is_empty()) \
				.override_failure_message("%s: Mercer Island touches %s by land" % [map.id, other_id]).is_false()
		# Seattle lies west of Bellevue; Renton south of Kirkland.
		assert_float(seattle[0].label_at.x).is_less(map.get_region("bellevue").label_at.x)
		assert_float(map.get_region("kirkland").label_at.y).is_less(map.get_region("renton").label_at.y)
		assert_int(map.water.size()).is_equal(1)
		assert_str(map.source).contains("Natural Earth")
		# The far side of Puget Sound is out.
		for kitsap in ["bremerton", "port_orchard", "poulsbo", "bainbridge_island"]:
			assert_bool(map.has_region(kitsap)).is_false()


func test_act1_variants_keep_the_start_trait_kinds() -> void:
	for variant: Dictionary in _plan().variants(0):
		var map := _load(variant["id"])
		assert_int(map.starts.size()).is_equal(3)
		assert_int(map.get_start("north_end").regions.size()).is_equal(2)
		var works := map.get_start("renton_works")
		assert_array(Array(works.regions)).contains_exactly(["renton"])
		assert_int(works.income_bonus[MapRegion.POWER]).is_equal(3)
		assert_float(works.material).is_equal(10.0)
		var substation := map.get_start("redmond_substation")
		assert_array(Array(substation.regions)).contains_exactly(["redmond"])
		assert_float(substation.pressure_rate_factor).is_equal(0.5)


func test_north_america_57_is_the_lower_48_with_neighbors() -> void:
	var map := _load("north_america_57")
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
	assert_bool(map.get_region("washington").is_adjacent_to("oregon")).is_true()
	assert_bool(map.get_region("washington").is_adjacent_to("british_columbia")).is_true()
	assert_bool(map.get_region("texas").is_adjacent_to("coahuila")).is_true()
	assert_bool(map.get_region("washington").is_adjacent_to("california")).is_false()
	assert_int(map.get_region("michigan").parts.size()).is_greater(0)


func test_the_act1_map_sits_in_each_act2_focus() -> void:
	var plan := _plan()
	for variant: Dictionary in plan.variants(1):
		var map := _load(variant["id"])
		var middle := Vector2.ZERO
		for p in map.zoom_inset:
			middle += p
		assert_str(map.region_at(middle / map.zoom_inset.size())).is_equal(variant["zoom_focus"])
		assert_bool(map.get_region(variant["zoom_focus"]).starts_owned).is_true()


func test_the_world_variants_find_regions_by_longitude_and_latitude() -> void:
	var places := {
		"world_8": {Vector2(-98, 39): "north_america", Vector2(-47.9, -15.8): "latin_america",
			Vector2(2.35, 48.85): "europe", Vector2(82.9, 55.0): "russia_central_asia",
			Vector2(31.2, 30.0): "middle_east_north_africa", Vector2(28, -26): "sub_saharan_africa",
			Vector2(116.4, 39.9): "asia", Vector2(134, -25): "oceania", Vector2(-53.0, 4.0): "latin_america"},
		"world_20": {Vector2(-98, 39): "united_states", Vector2(-75.7, 45.4): "canada",
			Vector2(-99.1, 19.4): "mexico_caribbean", Vector2(-53.0, 4.0): "brazil", Vector2(-64, -30): "andes",
			Vector2(2.35, 48.85): "western_europe", Vector2(13.4, 52.5): "northern_europe",
			Vector2(37.6, 55.75): "russia_west", Vector2(82.9, 55.0): "siberia", Vector2(44, 33): "middle_east",
			Vector2(77.2, 28.6): "south_asia", Vector2(139.7, 35.7): "east_asia", Vector2(151.2, -33.9): "oceania"},
		"world_39": {Vector2(-98, 39): "united_states", Vector2(-99.1, 19.4): "mexico",
			Vector2(-53.0, 4.0): "colombia_venezuela", Vector2(2.35, 48.85): "france", Vector2(-3.7, 40.4): "iberia",
			Vector2(13.4, 52.5): "germany", Vector2(12.5, 41.9): "italy", Vector2(82.9, 55.0): "russia",
			Vector2(51.4, 35.7): "iran", Vector2(77.2, 28.6): "india", Vector2(139.7, 35.7): "japan",
			Vector2(127, 37.5): "korea", Vector2(151.2, -33.9): "australia"},
	}
	for id: String in places:
		var map := _load(id)
		for at: Vector2 in places[id]:
			assert_str(map.region_at(at)).override_failure_message("%s: %s should be %s" % [id, at, places[id][at]]).is_equal(places[id][at])
		assert_str(map.region_at(Vector2(-30.0, 30.0))).is_empty()  # Mid-Atlantic
	var world := _load("world_20")
	assert_bool(world.crossing_between("united_states", "siberia").is_empty()).is_false()
