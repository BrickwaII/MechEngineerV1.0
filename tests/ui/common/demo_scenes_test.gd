extends GdUnitTestSuite
## The demo scenes build headless without errors.


func test_each_demo_scene_builds() -> void:
	for path in ["res://ui/common/demo/theme_demo.tscn", "res://ui/common/demo/feel_demo.tscn",
			"res://ui/common/demo/sprite_demo.tscn"]:
		var scene: Node = auto_free(load(path).instantiate())
		add_child(scene)
		await await_idle_frame()
		assert_int(scene.get_child_count()).override_failure_message(path).is_greater(1)
		scene.queue_free()


func test_the_feel_demo_lands_a_hit_on_every_meter() -> void:
	var demo: Node = auto_free(load("res://ui/common/demo/feel_demo.tscn").instantiate())
	add_child(demo)
	await await_idle_frame()
	demo._land_hit(12, false)
	assert_float(demo.ally_hp.value).is_equal(88.0)
	assert_float(demo.ally_hp.ghost).is_equal(100.0)
	demo.gain_energy()
	assert_float(demo.ally_energy.value).is_equal(55.0)
	await HitPause.finished(get_tree())
