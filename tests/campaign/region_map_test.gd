extends GdUnitTestSuite

const ACT1 := "res://data/regions/act1_placeholder.json"
const HARBOR := "res://data/regions/harbor_town_placeholder.json"


func test_act1_placeholder_loads_twelve_regions() -> void:
	var map := RegionMap.load_file(ACT1)
	assert_array(map.errors).is_empty()
	assert_int(map.regions.size()).is_equal(12)
	assert_str(map.id).is_equal("act1_placeholder")
	var origin := map.get_region("aurora_data_center")
	assert_str(origin.name).is_equal("Aurora Data Center")
	assert_int(origin.provides[MapRegion.POWER]).is_equal(2)
	assert_int(origin.provides[MapRegion.ENERGY]).is_equal(3)
	assert_int(origin.provides[MapRegion.MATERIAL]).is_equal(0)
	assert_bool(origin.starts_owned).is_true()
	assert_bool(origin.is_adjacent_to("hydro_dam")).is_true()


func test_a_different_region_file_loads_with_the_same_code() -> void:
	var map := RegionMap.load_file(HARBOR)
	assert_array(map.errors).is_empty()
	assert_int(map.regions.size()).is_equal(6)
	assert_array(Array(map.starting_ids())).contains_exactly(["old_town"])


func test_every_shipped_region_file_is_valid() -> void:
	var dir := DirAccess.open("res://data/regions")
	var count := 0
	for file in dir.get_files():
		if file.get_extension() != "json":
			continue
		count += 1
		var map := RegionMap.load_file("res://data/regions".path_join(file))
		assert_array(map.errors).override_failure_message("%s: %s" % [file, map.errors]).is_empty()
		for region in map.regions:
			assert_int(region.polygon.size()).is_greater_equal(3)
			assert_int(region.defense).is_between(0, 5)
			assert_int(region.pressure_base).is_between(1, 3)
	assert_int(count).is_greater_equal(2)


func test_label_defaults_to_the_polygon_centroid() -> void:
	var map := RegionMap.from_dict(_two_regions())
	assert_array(map.errors).is_empty()
	assert_vector(map.get_region("a").label_at).is_equal(Vector2(0.25, 0.5))


func test_one_way_adjacency_is_rejected() -> void:
	var data := _two_regions()
	data["regions"][1]["adjacent"] = []
	var map := RegionMap.from_dict(data)
	assert_bool(map.is_valid()).is_false()


func test_unknown_neighbor_is_rejected() -> void:
	var data := _two_regions()
	data["regions"][0]["adjacent"] = ["b", "nowhere"]
	assert_bool(RegionMap.from_dict(data).is_valid()).is_false()


func test_out_of_range_values_are_rejected() -> void:
	for change: Array in [["defense", 6], ["pressure_base", 0], ["pressure_base", 4], ["defense", 1.5]]:
		var data := _two_regions()
		data["regions"][0][change[0]] = change[1]
		assert_bool(RegionMap.from_dict(data).is_valid()) \
			.override_failure_message("accepted %s = %s" % change).is_false()


func test_points_outside_the_unit_square_are_rejected() -> void:
	var data := _two_regions()
	data["regions"][0]["polygon"] = [[0, 0], [1.2, 0], [0.5, 1]]
	assert_bool(RegionMap.from_dict(data).is_valid()).is_false()


func test_duplicate_ids_are_rejected() -> void:
	var data := _two_regions()
	data["regions"][1]["id"] = "a"
	assert_bool(RegionMap.from_dict(data).is_valid()).is_false()


func test_a_missing_file_reports_an_error() -> void:
	assert_bool(RegionMap.load_file("res://tests/campaign/no_such_file.json").is_valid()).is_false()


func test_broken_json_reports_an_error() -> void:
	assert_bool(RegionMap.from_json("{ not json").is_valid()).is_false()


static func _two_regions() -> Dictionary:
	return {
		"id": "pair",
		"name": "Pair",
		"regions": [
			{"id": "a", "name": "A", "kind": "Test", "polygon": [[0, 0], [0.5, 0], [0.5, 1], [0, 1]],
				"adjacent": ["b"], "provides": {"power": 1, "energy": 0, "material": 0},
				"defense": 0, "pressure_base": 1, "starts_owned": true},
			{"id": "b", "name": "B", "kind": "Test", "polygon": [[0.5, 0], [1, 0], [1, 1], [0.5, 1]],
				"adjacent": ["a"], "provides": {"power": 0, "energy": 2, "material": 0},
				"defense": 2, "pressure_base": 2, "starts_owned": false},
		],
	}


func test_short_name_defaults_to_the_name() -> void:
	var data := _two_regions()
	data["regions"][1]["short_name"] = "BB"
	var map := RegionMap.from_dict(data)
	assert_str(map.get_region("a").short_name).is_equal("A")
	assert_str(map.get_region("b").short_name).is_equal("BB")


func test_parts_are_drawn_and_clicked_like_the_polygon() -> void:
	var data := _two_regions()
	data["regions"][0]["polygon"] = [[0, 0], [0.2, 0], [0.2, 0.2], [0, 0.2]]
	data["regions"][0]["parts"] = [[[0, 0.8], [0.2, 0.8], [0.2, 1], [0, 1]]]
	var map := RegionMap.from_dict(data)
	assert_array(map.errors).is_empty()
	assert_int(map.get_region("a").shapes().size()).is_equal(2)
	assert_str(map.region_at(Vector2(0.1, 0.1))).is_equal("a")
	assert_str(map.region_at(Vector2(0.1, 0.9))).is_equal("a")
	assert_str(map.region_at(Vector2(0.1, 0.5))).is_empty()
	assert_str(map.region_at(Vector2(0.75, 0.5))).is_equal("b")


func test_a_globe_file_reads_longitude_and_latitude() -> void:
	var data := _two_regions()
	data["projection"] = RegionMap.GLOBE
	data["regions"][0]["polygon"] = [[-120, 30], [-80, 30], [-80, 50], [-120, 50]]
	data["regions"][1]["polygon"] = [[-80, 30], [-60, 30], [-60, 50], [-80, 50]]
	var map := RegionMap.from_dict(data)
	assert_array(map.errors).is_empty()
	assert_bool(map.is_globe()).is_true()
	assert_str(map.region_at(Vector2(-100, 40))).is_equal("a")
	# The same points are out of range on a flat map.
	data["projection"] = RegionMap.FLAT
	assert_bool(RegionMap.from_dict(data).is_valid()).is_false()
	data["projection"] = "mercator"
	assert_bool(RegionMap.from_dict(data).is_valid()).is_false()
	data["projection"] = RegionMap.GLOBE
	data["regions"][0]["polygon"] = [[-190, 30], [-80, 30], [-80, 50]]
	assert_bool(RegionMap.from_dict(data).is_valid()).is_false()


func test_crossings_must_join_adjacent_regions() -> void:
	var data := _two_regions()
	data["crossings"] = [{"between": ["a", "b"], "name": "Ferry"}]
	var map := RegionMap.from_dict(data)
	assert_array(map.errors).is_empty()
	assert_str(map.crossing_between("b", "a")["name"]).is_equal("Ferry")
	assert_int(map.crossing_ends(map.crossings[0]).size()).is_equal(2)
	data["crossings"] = [{"between": ["a", "nowhere"], "name": "Ferry"}]
	assert_bool(RegionMap.from_dict(data).is_valid()).is_false()
	data["crossings"] = [{"between": ["a"], "name": "Ferry"}]
	assert_bool(RegionMap.from_dict(data).is_valid()).is_false()
	data["crossings"] = [{"between": ["a", "b"], "name": "Ferry"}]
	data["regions"][0]["adjacent"] = []
	data["regions"][1]["adjacent"] = []
	assert_bool(RegionMap.from_dict(data).is_valid()).is_false()


func test_land_and_zoom_inset_are_read() -> void:
	var data := _two_regions()
	data["land"] = [[[0, 0], [0.1, 0], [0.1, 0.1]]]
	data["zoom_inset"] = [[0.1, 0.1], [0.3, 0.2]]
	var map := RegionMap.from_dict(data)
	assert_array(map.errors).is_empty()
	assert_int(map.land.size()).is_equal(1)
	assert_int(map.zoom_inset.size()).is_equal(2)
	data["zoom_inset"] = [[0.1, 0.1]]
	assert_bool(RegionMap.from_dict(data).is_valid()).is_false()
