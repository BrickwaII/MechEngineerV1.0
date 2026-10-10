extends GdUnitTestSuite
## The act 3 globe, headless: what is drawn where at a rotation, and that a
## click finds the region drawn under it at any rotation.

const GlobeView := preload("res://ui/overworld/globe_view.gd")
const WORLD := "res://data/regions/world.json"
const TUNING := "res://data/tuning/act3.json"

## Cities and the region each lies in, as longitude and latitude.
const CITIES := {
	"Kansas City": [Vector2(-94.6, 39.1), "united_states"],
	"Toronto": [Vector2(-79.4, 43.7), "canada"],
	"Mexico City": [Vector2(-99.1, 19.4), "mexico_central"],
	"Bogota": [Vector2(-74.1, 4.7), "north_andes"],
	"London": [Vector2(-0.1, 51.5), "british_isles"],
	"Paris": [Vector2(2.35, 48.85), "western_europe"],
	"Berlin": [Vector2(13.4, 52.5), "central_europe"],
	"Rome": [Vector2(12.5, 41.9), "mediterranean"],
	"Moscow": [Vector2(37.6, 55.75), "russia_west"],
	"Cairo": [Vector2(31.2, 30.0), "north_africa"],
	"Lagos": [Vector2(3.4, 6.5), "west_africa"],
	"Delhi": [Vector2(77.2, 28.6), "south_asia"],
	"Beijing": [Vector2(116.4, 39.9), "china"],
	"Tokyo": [Vector2(139.7, 35.7), "east_asia"],
	"Sydney": [Vector2(151.2, -33.9), "australia"],
}

var _view: Control


func before_test() -> void:
	var map := RegionMap.load_file(WORLD)
	var tuning := MapTuning.load_file(TUNING)
	assert_array(map.errors + tuning.errors).is_empty()
	_view = auto_free(GlobeView.new())
	add_child(_view)
	_view.size = Vector2(880, 620)
	_view.campaign = Campaign.new(map, tuning, StubSquadProvider.new(), StubFightService.new())


func _turn_to(lon: float, lat: float) -> void:
	_view.look_at_lonlat(Vector2(lon, lat))


## Checks every city that faces the viewer is found where it is drawn, and
## returns the names of those that do.
func _check_visible_cities() -> Array:
	var seen := []
	for city: String in CITIES:
		var at: Variant = _view.project_point(CITIES[city][0])
		if at == null:
			continue
		seen.append(city)
		assert_str(_view.region_at(at)).override_failure_message("%s at %s" % [city, at]).is_equal(CITIES[city][1])
	return seen


func test_the_globe_starts_facing_the_network() -> void:
	assert_str(_view.region_at(_view.size / 2.0)).is_equal("united_states")


func test_clicks_hit_the_region_drawn_there_facing_the_americas() -> void:
	_turn_to(-95.0, 35.0)
	var seen := _check_visible_cities()
	assert_array(seen).contains(["Kansas City", "Toronto", "Mexico City", "Bogota"])
	assert_array(seen).not_contains(["Tokyo", "Delhi", "Sydney", "Beijing"])
	assert_str(_view.region_at(_view.size / 2.0)).is_equal("united_states")


func test_clicks_hit_the_region_drawn_there_facing_europe() -> void:
	_turn_to(15.0, 45.0)
	var seen := _check_visible_cities()
	assert_array(seen).contains(["London", "Paris", "Berlin", "Rome", "Moscow", "Cairo", "Lagos"])
	assert_array(seen).not_contains(["Kansas City", "Sydney", "Tokyo"])
	assert_str(_view.region_at(_view.size / 2.0)).is_equal("mediterranean")


func test_the_same_spot_shows_different_regions_at_two_rotations() -> void:
	var spot: Vector2 = _view.size / 2.0 + Vector2(40, -30)
	_turn_to(-95.0, 35.0)
	var first: String = _view.region_at(spot)
	_turn_to(105.0, 35.0)
	var second: String = _view.region_at(spot)
	assert_str(first).is_equal("united_states")
	assert_str(second).is_equal("china")


func test_a_click_off_the_globe_or_on_the_ocean_finds_nothing() -> void:
	assert_str(_view.region_at(Vector2(2, 2))).is_empty()
	assert_object(_view.view_to_map(Vector2(2, 2))).is_null()
	_turn_to(-30.0, 30.0)  # The middle of the Atlantic.
	assert_str(_view.region_at(_view.size / 2.0)).is_empty()


func test_view_to_map_inverts_project_point() -> void:
	for rotation: Vector2 in [Vector2(-95, 35), Vector2(60, -20), Vector2(170, 60)]:
		_turn_to(rotation.x, rotation.y)
		for lonlat: Vector2 in [rotation, rotation + Vector2(20, 10), rotation + Vector2(-35, -25)]:
			var at: Variant = _view.project_point(lonlat)
			assert_object(at).is_not_null()
			var back: Vector2 = _view.view_to_map(at)
			assert_float(wrapf(back.x - lonlat.x, -180.0, 180.0)).is_equal_approx(0.0, 1e-3)
			assert_float(back.y).is_equal_approx(lonlat.y, 1e-3)


func test_the_far_side_is_not_drawn() -> void:
	_turn_to(-95.0, 35.0)
	assert_object(_view.project_point(CITIES["Beijing"][0])).is_null()
	assert_object(_view.label_position("china")).is_null()
	assert_object(_view.label_position("united_states")).is_not_null()
	var china := _view.campaign.map.get_region("china")
	assert_array(_view.project_shape(china.polygon)).is_empty()


func test_outlines_over_the_rim_are_clipped_to_the_disk() -> void:
	# Facing the Atlantic, the Americas and Europe both run over the rim.
	_turn_to(-30.0, 20.0)
	var middle: Vector2 = _view.size / 2.0
	var limit: float = _view.radius() + 0.5
	var clipped := 0
	for region_id in ["siberia", "canada", "south_asia", "united_states"]:
		for shape in _view.campaign.map.get_region(region_id).shapes():
			for points: PackedVector2Array in _view.project_shape(shape):
				clipped += 1
				for p in points:
					assert_float(p.distance_to(middle)).is_less_equal(limit)
	assert_int(clipped).is_greater(0)


func test_dragging_turns_the_globe_and_the_poles_stop_at_the_tilt_limit() -> void:
	_turn_to(0.0, 0.0)
	var per_pixel: float = _view.campaign.tuning.globe_degrees_per_pixel
	_view.drag_by(Vector2(100, 0))
	assert_float(_view.center_lon).is_equal_approx(-100.0 * per_pixel, 1e-6)
	_view.drag_by(Vector2(0, 50))
	assert_float(_view.center_lat).is_equal_approx(50.0 * per_pixel, 1e-6)
	_view.drag_by(Vector2(0, 100000))
	assert_float(_view.center_lat).is_equal(_view.campaign.tuning.globe_max_tilt)
	_view.drag_by(Vector2(-1000.0 / per_pixel, 0))
	assert_float(_view.center_lon).is_between(-180.0, 180.0)


func test_a_click_selects_and_a_drag_turns_without_selecting() -> void:
	_turn_to(-95.0, 35.0)
	var at: Vector2 = _view.project_point(CITIES["Kansas City"][0])
	_press(at, true)
	_press(at, false)
	assert_str(_view.selected_id).is_equal("united_states")
	_view.selected_id = ""
	var lon_before: float = _view.center_lon
	_press(at, true)
	var motion := InputEventMouseMotion.new()
	motion.position = at + Vector2(60, 0)
	motion.relative = Vector2(60, 0)
	_view._gui_input(motion)
	_press(at + Vector2(60, 0), false)
	assert_str(_view.selected_id).is_empty()
	assert_float(_view.center_lon).is_not_equal(lon_before)


func _press(at: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = at
	_view._gui_input(event)
