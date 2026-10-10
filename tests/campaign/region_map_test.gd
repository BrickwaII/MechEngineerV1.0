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
