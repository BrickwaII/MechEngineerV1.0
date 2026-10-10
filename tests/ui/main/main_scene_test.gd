extends GdUnitTestSuite


func test_main_scene_loads_and_runs() -> void:
	var runner := scene_runner("res://ui/main/main.tscn")
	await runner.simulate_frames(2)
	assert_object(runner.scene()).is_not_null()
	assert_str(runner.scene().name).is_equal("Main")


func test_pressing_play_opens_a_new_run_on_the_draft() -> void:
	var runner := scene_runner("res://ui/main/main.tscn")
	await runner.simulate_frames(2)
	var flow := runner.scene().get_node("RunFlow") as RunFlow
	assert_object(flow).is_not_null()
	assert_int(flow.stage).is_equal(RunFlow.Stage.DRAFT)
	assert_object(flow.draft_screen).is_not_null()
