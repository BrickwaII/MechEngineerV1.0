extends GdUnitTestSuite


func test_main_scene_loads_and_runs() -> void:
	var runner := scene_runner("res://ui/main/main.tscn")
	await runner.simulate_frames(2)
	assert_object(runner.scene()).is_not_null()
	assert_str(runner.scene().name).is_equal("Main")
