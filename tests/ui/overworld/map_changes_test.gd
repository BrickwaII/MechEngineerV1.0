extends GdUnitTestSuite
## MapChanges: what changed on the map between two snapshots.


func _snap(owned: Array, energy: float, material: float, grid: float) -> Dictionary:
	return {"owned": PackedStringArray(owned), "energy": energy, "material": material, "grid": grid}


func test_captures_losses_and_resource_moves() -> void:
	var c := MapChanges.between(_snap(["a", "b"], 10, 5, 80), _snap(["a", "c"], 14, 5, 70))
	assert_array(Array(c.captured)).contains_exactly(["c"])
	assert_array(Array(c.lost)).contains_exactly(["b"])
	assert_dict(c.deltas).is_equal({"energy": 4.0, "grid": -10.0})
	assert_bool(c.is_empty()).is_false()


func test_nothing_changed_is_empty() -> void:
	var s := _snap(["a"], 1, 2, 3)
	assert_bool(MapChanges.between(s, s).is_empty()).is_true()
	# Fractions below half a point do not pop.
	assert_bool(MapChanges.between(s, _snap(["a"], 1.2, 2, 3)).is_empty()).is_true()


func test_changes_that_pile_up_out_of_sight_merge() -> void:
	var first := MapChanges.between(_snap(["a"], 0, 0, 100), _snap(["a", "b"], 4, 0, 90))
	first.merge(MapChanges.between(_snap(["a", "b"], 4, 0, 90), _snap(["a", "b", "c"], 8, 2, 90)))
	assert_array(Array(first.captured)).contains_exactly(["b", "c"])
	assert_dict(first.deltas).is_equal({"energy": 8.0, "grid": -10.0, "material": 2.0})


func test_a_region_taken_then_lost_cancels_out() -> void:
	var first := MapChanges.between(_snap(["a"], 0, 0, 0), _snap(["a", "b"], 0, 0, 0))
	first.merge(MapChanges.between(_snap(["a", "b"], 0, 0, 0), _snap(["a"], 0, 0, 0)))
	assert_bool(first.is_empty()).is_true()


func test_a_snapshot_reads_the_run_state() -> void:
	var state := RunState.new()
	state.owned = PackedStringArray(["x"])
	state.energy = 3.0
	state.material = 4.0
	state.grid = 50.0
	var snap := MapChanges.snapshot(state)
	assert_dict(snap).is_equal(_snap(["x"], 3, 4, 50))
	state.owned.append("y")
	assert_int((snap["owned"] as PackedStringArray).size()).is_equal(1)
